#!/usr/bin/env python3
"""
courtauction_result.csv 파일을 Firestore에 업로드
+ 각 경매 물건의 주소로 실거래가 자동 매칭
+ Kakao API로 좌표 변환
+ Flutter 앱 지도에 표시

사용법:
  python upload_csv.py courtauction_result.csv
  python upload_csv.py courtauction_result.csv --skip-trade  # 실거래가 매칭 생략
  python upload_csv.py courtauction_result.csv --limit 20    # 처음 20건만 테스트
"""

import argparse
import os
import sys
import time
from datetime import datetime

from google.cloud import firestore

from src.config import TRADE_FIELDS, OFFICETEL_TRADE_FIELDS
from src.csv_parser import parse_csv
from src.geocoder import geocode
from src.matcher import extract_region_from_address
from src.region_code import search_region
from src.scraper import RealEstateScraper

FIREBASE_KEY_PATH = os.path.join(os.path.dirname(__file__), "firebase-key.json")


def _normalize_apt_name(name):
    """아파트명 정규화: 공백/특수문자/접미사/차수/단지 제거"""
    import re as _re
    s = _re.sub(r'[\s\-_·()（）,.]', '', name)
    # 흔한 접미사
    s = s.replace("아파트", "").replace("APT", "").replace("apt", "")
    # N차, N단지 제거 (예: "성복자이1차" → "성복자이")
    s = _re.sub(r'\d+차', '', s)
    s = _re.sub(r'\d+단지', '', s)
    # 연속 숫자도 꼬리에서 정리 (예: "파크앤시티타워2" → "파크앤시티타워")
    s = _re.sub(r'\d+$', '', s)
    return s


def _match_apt_name(trade_apt, target_set):
    """
    실거래가 아파트명 ↔ CSV 아파트명 매칭
    - 정확 일치
    - 정규화 후 일치 (공백/접미사/차수 제거)
    - 부분 포함 (3자 이상)
    - 유사도 70% 이상 (difflib)
    """
    if not trade_apt:
        return False
    from difflib import SequenceMatcher

    trade_norm = _normalize_apt_name(trade_apt)
    for target in target_set:
        if trade_apt == target:
            return True
        target_norm = _normalize_apt_name(target)
        if not trade_norm or not target_norm:
            continue
        if trade_norm == target_norm:
            return True
        # 한쪽이 다른쪽에 포함 (3자 이상)
        if len(trade_norm) >= 3 and len(target_norm) >= 3:
            if trade_norm in target_norm or target_norm in trade_norm:
                return True
        # 유사도 매칭 (두 이름 모두 4자 이상, 70% 이상 일치)
        if len(trade_norm) >= 4 and len(target_norm) >= 4:
            ratio = SequenceMatcher(None, trade_norm, target_norm).ratio()
            if ratio >= 0.7:
                return True
    return False


def _find_matching_target(trade_apt, target_set):
    """매칭된 target 이름 반환 (디버그용)"""
    if not trade_apt:
        return None
    from difflib import SequenceMatcher
    trade_norm = _normalize_apt_name(trade_apt)
    best = (0.0, None)
    for target in target_set:
        target_norm = _normalize_apt_name(target)
        if not target_norm:
            continue
        if trade_norm == target_norm:
            return target
        if len(trade_norm) >= 3 and len(target_norm) >= 3:
            if trade_norm in target_norm or target_norm in trade_norm:
                return target
        if len(trade_norm) >= 4 and len(target_norm) >= 4:
            ratio = SequenceMatcher(None, trade_norm, target_norm).ratio()
            if ratio > best[0]:
                best = (ratio, target)
    return best[1] if best[0] >= 0.7 else None


def get_db():
    if not os.path.exists(FIREBASE_KEY_PATH):
        print("[오류] firebase-key.json 파일이 없습니다. 프로젝트 루트에 배치하세요.")
        sys.exit(1)
    return firestore.Client.from_service_account_json(FIREBASE_KEY_PATH)


def get_data_go_kr_key():
    # 1) 환경변수 우선
    key = os.environ.get("DATA_GO_KR_API_KEY")
    if key:
        return key
    # 2) 프로젝트 루트의 .env 파일
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if os.path.exists(env_path):
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("DATA_GO_KR_API_KEY="):
                    val = line.split("=", 1)[1].strip().strip("\"'")
                    if val:
                        return val
        print(f"  [정보] {env_path} 파일은 있지만 DATA_GO_KR_API_KEY가 없습니다")
    else:
        print(f"  [정보] .env 파일을 찾지 못했습니다: {env_path}")
    return ""


def batch_upload(db, collection_name, docs, batch_size=400):
    """Firestore batch 업로드"""
    collection = db.collection(collection_name)
    batch = db.batch()
    count = 0

    for doc_data in docs:
        doc_data["_uploaded_at"] = firestore.SERVER_TIMESTAMP
        batch.set(collection.document(), doc_data)
        count += 1
        if count % batch_size == 0:
            batch.commit()
            batch = db.batch()
            print(f"    {count}건 업로드됨...")

    if count % batch_size != 0:
        batch.commit()

    return count


def main():
    parser = argparse.ArgumentParser(description="경매 CSV → Firestore 업로드")
    parser.add_argument("csv_file", help="CSV 파일 경로")
    parser.add_argument("--skip-trade", action="store_true",
                        help="실거래가 매칭 생략 (경매 데이터만 업로드)")
    parser.add_argument("--skip-geocode", action="store_true",
                        help="좌표 변환 생략 (오래 걸림 방지)")
    parser.add_argument("--limit", type=int, default=0,
                        help="처음 N건만 처리 (테스트용)")
    parser.add_argument("--api-key", default="",
                        help="data.go.kr API 키 (환경변수/.env 대신 직접 전달)")
    parser.add_argument("--months", type=int, default=6,
                        help="실거래가 조회 개월 수 (기본 6개월, 각 아파트의 최신 거래만 업로드)")
    args = parser.parse_args()

    # CSV 파싱
    print(f"\n{'='*60}")
    print(f"[1/4] CSV 파싱: {args.csv_file}")
    print(f"{'='*60}")

    if not os.path.exists(args.csv_file):
        print(f"[오류] 파일을 찾을 수 없습니다: {args.csv_file}")
        sys.exit(1)

    auction_items = parse_csv(args.csv_file)
    print(f"  → {len(auction_items)}건 파싱 완료")

    if args.limit > 0:
        auction_items = auction_items[: args.limit]
        print(f"  → --limit {args.limit} 옵션: 처음 {len(auction_items)}건만 처리")

    # 좌표 변환 + 시군구 추출
    print(f"\n{'='*60}")
    print(f"[2/4] 주소 → 좌표 변환 (Kakao API)")
    print(f"{'='*60}")

    region_codes_found = set()

    if args.skip_geocode:
        print("  --skip-geocode 옵션: 좌표 변환 생략")
    else:
        for i, item in enumerate(auction_items):
            addr = item["주소"]

            # 시군구 코드 추출
            region_info = extract_region_from_address(addr)
            if region_info:
                district_name, region_code = region_info
                item["_region_name"] = district_name
                item["_region_code"] = region_code
                region_codes_found.add(region_code)
            else:
                item["_region_code"] = ""
                item["_region_name"] = ""

            # 좌표 변환 - 아파트명이 있으면 더 정확한 주소 사용
            geocode_query = addr
            if item.get("아파트명"):
                geocode_query = f"{addr.rsplit(' ', 1)[0] if ' ' in addr else addr} {item['아파트명']}"

            coords = geocode(geocode_query)
            if not coords:
                coords = geocode(addr)  # 원주소로 재시도

            if coords:
                item["lat"] = coords["lat"]
                item["lng"] = coords["lng"]
            else:
                item["lat"] = 0.0
                item["lng"] = 0.0

            if (i + 1) % 10 == 0:
                print(f"  [{i+1}/{len(auction_items)}] 처리 중...")

            time.sleep(0.1)  # Kakao API rate limit

        valid = [a for a in auction_items if a.get("lat", 0) != 0]
        print(f"  → {len(valid)}/{len(auction_items)}건 좌표 변환 성공")

    # 실거래가 매칭 — CSV에 있는 아파트만 필터링
    all_trades = []
    if not args.skip_trade and region_codes_found:
        print(f"\n{'='*60}")
        print(f"[3/4] 실거래가 매칭 ({len(region_codes_found)}개 지역)")
        print(f"{'='*60}")

        service_key = args.api_key or get_data_go_kr_key()
        if not service_key:
            print("  [경고] DATA_GO_KR_API_KEY가 없어 실거래가 매칭을 생략합니다")
            print("  해결: .env 파일에 'DATA_GO_KR_API_KEY=...' 추가")
            print("        또는 --api-key 옵션으로 전달")
        else:
            trade_scraper = RealEstateScraper(service_key)

            def _gen_months(skip, count):
                """지난달부터 skip개월 건너뛰고 count개월치 YYYYMM 생성"""
                result = []
                now = datetime.now()
                y, m = now.year, now.month
                # skip만큼 과거로
                for _ in range(skip):
                    m -= 1
                    if m == 0:
                        m = 12
                        y -= 1
                # count개월 수집
                for _ in range(count):
                    m -= 1
                    if m == 0:
                        m = 12
                        y -= 1
                    result.append("{:04d}{:02d}".format(y, m))
                return result

            # 1차: 최근 6개월 (지난달 ~ 6개월 전)
            initial_months = _gen_months(skip=1, count=6)
            # 2차(확장): 7개월 ~ 12개월 전 (미매칭 아파트용)
            extension_months = _gen_months(skip=7, count=6)

            # 하위호환: --months 옵션이 주어지면 초기 기간으로 적용
            if args.months != 6:
                initial_months = _gen_months(skip=1, count=args.months)
                extension_months = []  # 명시적 지정 시 확장 비활성화

            months_to_fetch = initial_months

            print("  조회 개월: {} ({}개월)".format(
                ", ".join(months_to_fetch), len(months_to_fetch)))

            # CSV에서 지역별 아파트명 목록 수집
            target_apts = {}  # {region_code: set(아파트명)}
            # 경매 좌표 재사용용: 정규화된 아파트명 → (lat, lng)
            apt_coords = {}
            for item in auction_items:
                code = item.get("_region_code", "")
                apt = item.get("아파트명", "").strip()
                if code and apt:
                    target_apts.setdefault(code, set()).add(apt)
                lat = item.get("lat", 0)
                lng = item.get("lng", 0)
                if apt and lat and lng:
                    apt_coords[_normalize_apt_name(apt)] = (lat, lng)

            print("  매칭 대상 아파트:")
            for code, apts in target_apts.items():
                print("    {} → {}".format(code, ", ".join(sorted(apts)[:5])))
                if len(apts) > 5:
                    print("         ... 외 {}개".format(len(apts) - 5))
            print("  경매 좌표 캐시: {}건".format(len(apt_coords)))

            # 지역별로 6개월치 조회 후 아파트+면적 단위 최신 거래만 선택
            for code in region_codes_found:
                region_name = code
                for r in search_region(code):
                    region_name = "{} {}".format(r[0], r[1])
                    break

                apt_names = target_apts.get(code, set())
                if not apt_names:
                    print("  {} ({}) → 매칭할 아파트명 없음, 건너뜀".format(region_name, code))
                    continue

                print("  {} ({}) 조회 중...".format(region_name, code))

                # (아파트명, 전용면적)별로 모든 매칭 거래를 수집 후 정렬
                trade_groups = {}  # key → list[(date_int, row_dict)]
                total_fetched = 0
                matched_target_apts = set()  # 매칭된 CSV 아파트명
                sample_unmatched = {}  # 샘플: 매칭 안된 실거래가 아파트명 (최대 10개)

                def _process_df(df, target_set, trade_type):
                    """dataframe의 각 행을 매칭해서 trade_groups에 추가. 매칭 수 반환"""
                    count = 0
                    for _, row in df.iterrows():
                        trade_apt = str(row.get("아파트명", row.get("aptNm", row.get("offiNm", "")))).strip()
                        matched = _find_matching_target(trade_apt, target_set)
                        if not matched:
                            if trade_apt and len(sample_unmatched) < 10:
                                sample_unmatched[trade_apt] = True
                            continue
                        matched_target_apts.add(matched)

                        try:
                            yy = int(row.get("년", row.get("dealYear", 0)))
                            mm = int(row.get("월", row.get("dealMonth", 0)))
                            dd = int(row.get("일", row.get("dealDay", 0)))
                            date_int = yy * 10000 + mm * 100 + dd
                        except (ValueError, TypeError):
                            date_int = 0

                        area = str(row.get("전용면적(㎡)", row.get("excluUseAr", ""))).strip()
                        key = (matched, area)
                        row_dict = row.to_dict()
                        row_dict["_matched_auction_apt"] = matched
                        row_dict["_trade_type"] = trade_type
                        trade_groups.setdefault(key, []).append((date_int, row_dict))
                        count += 1
                    return count

                for ym in months_to_fetch:
                    # 1) 아파트매매
                    df_apt = trade_scraper._fetch("아파트매매", code, ym, TRADE_FIELDS)
                    apt_total = len(df_apt) if not df_apt.empty else 0
                    apt_matched = _process_df(df_apt, apt_names, "아파트매매") if apt_total else 0

                    # 2) 오피스텔매매 (파크앤시티타워 같은 물건 커버)
                    df_offi = trade_scraper._fetch("오피스텔매매", code, ym, OFFICETEL_TRADE_FIELDS)
                    offi_total = len(df_offi) if not df_offi.empty else 0
                    offi_matched = _process_df(df_offi, apt_names, "오피스텔매매") if offi_total else 0

                    total_fetched += apt_total + offi_total
                    if apt_total == 0 and offi_total == 0:
                        print("    {} → 0건".format(ym))
                    else:
                        print("    {} → 아파트 {}건({}매칭) / 오피스텔 {}건({}매칭)".format(
                            ym, apt_total, apt_matched, offi_total, offi_matched))

                print("    → 6개월 합계 {}건 조회, {}건 아파트(+면적) 그룹".format(
                    total_fetched, len(trade_groups)))

                # 하이브리드: 미매칭이 있으면 추가 6개월(7~12개월 전) 확장 조회
                unmatched_targets = apt_names - matched_target_apts
                if unmatched_targets and extension_months:
                    print("    [확장] 미매칭 {}건 추가 조회 (7~12개월 전, 아파트+오피스텔)".format(
                        len(unmatched_targets)))
                    ext_matched_count = 0
                    for ym in extension_months:
                        df_apt = trade_scraper._fetch(
                            "아파트매매", code, ym, TRADE_FIELDS)
                        if not df_apt.empty:
                            ext_matched_count += _process_df(
                                df_apt, unmatched_targets, "아파트매매")
                        df_offi = trade_scraper._fetch(
                            "오피스텔매매", code, ym, OFFICETEL_TRADE_FIELDS)
                        if not df_offi.empty:
                            ext_matched_count += _process_df(
                                df_offi, unmatched_targets, "오피스텔매매")

                    new_matched = matched_target_apts - (apt_names - unmatched_targets)
                    print("    [확장] → 추가 매칭 {}건, 아파트 {}개 구제".format(
                        ext_matched_count, len(new_matched)))
                    unmatched_targets = apt_names - matched_target_apts

                # 매칭 진단 (확장 후 최종)
                if unmatched_targets:
                    print("    [진단] CSV에 있지만 실거래가 매칭 실패: {}개".format(
                        len(unmatched_targets)))
                    for u in sorted(unmatched_targets)[:10]:
                        print("      - {}".format(u))
                    if len(unmatched_targets) > 10:
                        print("      ... 외 {}개".format(len(unmatched_targets) - 10))
                    if sample_unmatched:
                        print("    [참고] 이 지역 실거래가 아파트명 예시:")
                        for u in list(sample_unmatched.keys())[:10]:
                            print("      - {}".format(u))

                for (apt_name, _area), trades in trade_groups.items():
                    # 날짜 역순 정렬, 상위 3건 추출
                    trades.sort(key=lambda t: t[0], reverse=True)
                    top3 = trades[:3]
                    latest_row = top3[0][1]

                    # 최근 3건 요약 배열
                    recent_trades = []
                    for date_int, row_dict in top3:
                        recent_trades.append({
                            "거래금액": str(row_dict.get("거래금액(만원)", row_dict.get("dealAmount", ""))).strip(),
                            "년": int(row_dict.get("년", row_dict.get("dealYear", 0)) or 0),
                            "월": int(row_dict.get("월", row_dict.get("dealMonth", 0)) or 0),
                            "일": int(row_dict.get("일", row_dict.get("dealDay", 0)) or 0),
                            "층": str(row_dict.get("층", row_dict.get("floor", ""))).strip(),
                            "전용면적": str(row_dict.get("전용면적(㎡)", row_dict.get("excluUseAr", ""))).strip(),
                        })

                    trade_data = dict(latest_row)  # 최신 거래를 base로
                    trade_data["_region_code"] = code
                    trade_data["_region_name"] = region_name
                    trade_data["_trade_type"] = "아파트매매"
                    trade_data["_type"] = "trade"
                    trade_data["최근거래"] = recent_trades
                    trade_data["거래건수"] = len(trades)
                    trade_data["거래건수_6개월"] = len(trades)  # 하위호환

                    # 좌표 우선순위:
                    #   1) 경매 캐시 (같은 아파트의 경매 좌표 재사용 - 가장 정확)
                    #   2) 카카오 geocoding
                    cached = apt_coords.get(_normalize_apt_name(apt_name))
                    if cached:
                        trade_data["lat"] = cached[0]
                        trade_data["lng"] = cached[1]
                        trade_data["_coord_source"] = "auction_cache"
                    elif not args.skip_geocode:
                        dong = trade_data.get("법정동", trade_data.get("umdNm", ""))
                        trade_addr = "{} {} {}".format(region_name, dong, apt_name)
                        coords = geocode(trade_addr)
                        if coords:
                            trade_data["lat"] = coords["lat"]
                            trade_data["lng"] = coords["lng"]
                            trade_data["_coord_source"] = "geocode"
                        else:
                            trade_data["lat"] = 0.0
                            trade_data["lng"] = 0.0
                            trade_data["_coord_source"] = "failed"
                        time.sleep(0.1)
                    else:
                        trade_data["lat"] = 0.0
                        trade_data["lng"] = 0.0

                    all_trades.append(trade_data)

            # 좌표 소스별 집계
            cache_count = sum(1 for t in all_trades if t.get("_coord_source") == "auction_cache")
            geo_count = sum(1 for t in all_trades if t.get("_coord_source") == "geocode")
            fail_count = sum(1 for t in all_trades if t.get("_coord_source") == "failed")
            print("  → 실거래가 총 {}건 (각 아파트+면적별 1건, 최근 3개월 이력 포함)".format(
                len(all_trades)))
            print("    좌표 출처: 경매캐시 {}건, geocode {}건, 실패 {}건".format(
                cache_count, geo_count, fail_count))

    # 실거래가를 경매 데이터에 임베드 (한 아파트 = 한 마커)
    print(f"\n{'='*60}")
    print(f"[3.5/4] 실거래가를 경매 데이터에 임베드")
    print(f"{'='*60}")

    trade_lookup = {}  # normalized_apt → list of {전용면적, 최근거래, 거래건수}
    for trade in all_trades:
        apt = trade.get("아파트명", trade.get("aptNm", ""))
        if not apt:
            continue
        norm = _normalize_apt_name(apt)
        trade_lookup.setdefault(norm, []).append({
            "전용면적": str(trade.get("전용면적(㎡)", trade.get("excluUseAr", ""))),
            "최근거래": trade.get("최근거래", []),
            "거래건수_6개월": trade.get("거래건수_6개월", 0),
        })

    attached_count = 0
    for auction in auction_items:
        apt = auction.get("아파트명", "")
        if not apt:
            auction["실거래가목록"] = []
            continue
        norm = _normalize_apt_name(apt)
        groups = trade_lookup.get(norm, [])
        auction["실거래가목록"] = groups
        if groups:
            attached_count += 1

    print("  → 경매 {}건 중 {}건에 실거래가 첨부됨".format(
        len(auction_items), attached_count))

    # Firestore 업로드
    print(f"\n{'='*60}")
    print(f"[4/4] Firestore 업로드")
    print(f"{'='*60}")

    db = get_db()

    # 경매 데이터 타입 지정
    for item in auction_items:
        item["_type"] = "auction"
        item["_source"] = "courtauction_csv"

    print(f"  경매 {len(auction_items)}건 업로드 중 (실거래가 임베드됨)...")
    auction_count = batch_upload(db, "map_items", auction_items)

    # 실거래가는 별도 마커로 업로드하지 않음 (경매에 임베드되어 있음)
    trade_count = 0
    if False and all_trades:
        print(f"  실거래가 {len(all_trades)}건 업로드 중...")
        trade_count = batch_upload(db, "map_items", all_trades)
    else:
        trade_count = 0

    # 업로드 로그
    db.collection("upload_log").add({
        "command": "upload_csv",
        "csv_file": os.path.basename(args.csv_file),
        "auction_count": auction_count,
        "trade_count": trade_count,
        "uploaded_at": firestore.SERVER_TIMESTAMP,
    })

    print(f"\n{'='*60}")
    print(f"  완료! 경매 {auction_count}건 + 실거래가 {trade_count}건")
    print(f"  Flutter 앱에서 지도를 열면 데이터가 표시됩니다.")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
