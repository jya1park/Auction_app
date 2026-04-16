#!/usr/bin/env python3
"""
경매 → 실거래가 매칭 → 좌표 변환 → Firestore 업로드

핵심 흐름:
  1. 법원 경매 물건을 크롤링
  2. 각 물건 소재지에서 시군구를 추출하여 실거래가 자동 조회
  3. Kakao API로 주소 → 위경도 좌표 변환
  4. 경매 + 실거래가 + 좌표를 묶어서 Firestore에 업로드
  5. Flutter 앱 지도에서 바로 조회

사전 준비:
  .env 파일에 아래 3개 키 설정:
    DATA_GO_KR_API_KEY=...    (data.go.kr 실거래가 API)
    KAKAO_REST_API_KEY=...    (Kakao Developers REST API)
  프로젝트 루트에 firebase-key.json 배치 (Firebase 서비스 계정 키)

사용법:
  # 경매 크롤링 → 실거래가 매칭 → 지도 데이터 업로드 (한 번에!)
  python upload.py run --court 서울중앙 --usage 아파트
  python upload.py run --court 수원 --usage 아파트 --year-month 202502

  # 개별 실행도 가능
  python upload.py trade --region-code 11680 --year-month 202502
  python upload.py auction --court 서울중앙 --usage 아파트
"""

import argparse
import os
import sys
import time
from datetime import datetime

from google.cloud import firestore

from src.auction import AuctionScraper
from src.config import API_ENDPOINTS, RENT_FIELDS, TRADE_FIELDS
from src.geocoder import geocode
from src.matcher import extract_dong_from_address, extract_region_from_address
from src.region_code import search_region
from src.scraper import RealEstateScraper

FIREBASE_KEY_PATH = os.path.join(os.path.dirname(__file__), "firebase-key.json")


def get_db() -> firestore.Client:
    if not os.path.exists(FIREBASE_KEY_PATH):
        print("=" * 60)
        print("[오류] firebase-key.json 파일이 없습니다.")
        print()
        print("설정 방법:")
        print("  1. https://console.firebase.google.com 접속")
        print("  2. 프로젝트 생성 → Firestore Database 만들기")
        print("  3. 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성")
        print("  4. firebase-key.json으로 프로젝트 루트에 저장")
        print("=" * 60)
        sys.exit(1)
    return firestore.Client.from_service_account_json(FIREBASE_KEY_PATH)


def get_service_key() -> str:
    key = os.environ.get("DATA_GO_KR_API_KEY")
    if key:
        return key
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    if os.path.exists(env_path):
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("DATA_GO_KR_API_KEY="):
                    return line.split("=", 1)[1].strip().strip("\"'")
    print("[오류] DATA_GO_KR_API_KEY가 설정되지 않았습니다.")
    sys.exit(1)


def _batch_upload(db, collection_name: str, docs: list[dict]) -> int:
    """Firestore batch 업로드 (500건 제한 자동 처리)"""
    collection = db.collection(collection_name)
    batch = db.batch()
    count = 0

    for doc_data in docs:
        doc_data["_uploaded_at"] = firestore.SERVER_TIMESTAMP
        batch.set(collection.document(), doc_data)
        count += 1
        if count % 400 == 0:
            batch.commit()
            batch = db.batch()
            print(f"    {count}건 업로드됨...")

    if count % 400 != 0:
        batch.commit()

    return count


# ─────────────────────────────────────────────
#  run: 통합 파이프라인 (경매 → 실거래가 매칭 → 좌표 → 업로드)
# ─────────────────────────────────────────────

def cmd_run(args):
    """통합 파이프라인: 경매 크롤링 → 실거래가 매칭 → 좌표 변환 → 업로드"""
    db = get_db()
    service_key = get_service_key()
    trade_scraper = RealEstateScraper(service_key)
    auction_scraper = AuctionScraper()

    court = args.court or None
    usage = args.usage or None
    keyword = args.keyword or None
    year_month = args.year_month or datetime.now().strftime("%Y%m")

    # ── 1단계: 경매 크롤링 ──
    print(f"\n{'='*60}")
    print(f"[1/4] 경매 물건 크롤링")
    print(f"  법원: {court or '전체'} / 용도: {usage or '전체'}")
    print(f"{'='*60}")

    auction_items = auction_scraper.search(
        court_name=court, usage=usage, search_word=keyword
    )
    if not auction_items:
        print("  경매 물건이 없습니다.")
        return

    print(f"  → {len(auction_items)}건 수집")

    # ── 2단계: 주소에서 시군구 추출 & 좌표 변환 ──
    print(f"\n{'='*60}")
    print(f"[2/4] 주소 → 좌표 변환 (Geocoding)")
    print(f"{'='*60}")

    region_codes_found = set()  # 매칭에 사용할 시군구 코드들

    for i, item in enumerate(auction_items):
        addr = item.get("소재지", "")
        print(f"  [{i+1}/{len(auction_items)}] {addr[:40]}...")

        # 시군구 코드 추출
        region_info = extract_region_from_address(addr)
        if region_info:
            district_name, region_code = region_info
            item["_region_name"] = district_name
            item["_region_code"] = region_code
            item["_dong"] = extract_dong_from_address(addr)
            region_codes_found.add(region_code)
        else:
            item["_region_code"] = ""
            item["_region_name"] = ""
            item["_dong"] = ""

        # 좌표 변환
        coords = geocode(addr)
        if coords:
            item["lat"] = coords["lat"]
            item["lng"] = coords["lng"]
        else:
            item["lat"] = 0.0
            item["lng"] = 0.0

        time.sleep(0.15)  # Kakao API rate limit

    valid_auction = [a for a in auction_items if a.get("lat", 0) != 0]
    print(f"  → {len(valid_auction)}/{len(auction_items)}건 좌표 변환 성공")

    # ── 3단계: 실거래가 매칭 ──
    print(f"\n{'='*60}")
    print(f"[3/4] 실거래가 매칭 ({len(region_codes_found)}개 지역)")
    print(f"{'='*60}")

    all_trades = []
    for code in region_codes_found:
        # 지역명 조회
        region_name = code
        for r in search_region(code):
            region_name = f"{r[0]} {r[1]}"
            break

        print(f"  {region_name} ({code}) - {year_month} 조회 중...")
        field_map = TRADE_FIELDS
        df = trade_scraper._fetch("아파트매매", code, year_month, field_map)

        if df.empty:
            print(f"    → 0건")
            continue

        print(f"    → {len(df)}건")

        # 각 실거래가 항목에 좌표 추가
        for _, row in df.iterrows():
            trade_data = row.to_dict()
            trade_data["_region_code"] = code
            trade_data["_region_name"] = region_name
            trade_data["_trade_type"] = "아파트매매"

            # 실거래가 주소로 좌표 변환
            dong = trade_data.get("법정동", trade_data.get("umdNm", ""))
            apt_name = trade_data.get("아파트명", trade_data.get("aptNm", ""))
            trade_addr = f"{region_name} {dong} {apt_name}"

            coords = geocode(trade_addr)
            if coords:
                trade_data["lat"] = coords["lat"]
                trade_data["lng"] = coords["lng"]
            else:
                trade_data["lat"] = 0.0
                trade_data["lng"] = 0.0

            all_trades.append(trade_data)
            time.sleep(0.1)

    valid_trades = [t for t in all_trades if t.get("lat", 0) != 0]
    print(f"  → 실거래가 총 {len(all_trades)}건 ({len(valid_trades)}건 좌표 포함)")

    # ── 4단계: Firestore 업로드 ──
    print(f"\n{'='*60}")
    print(f"[4/4] Firestore 업로드")
    print(f"{'='*60}")

    # 경매 데이터 업로드
    for item in auction_items:
        item["_type"] = "auction"
        item["_court"] = court or "전체"
        item["_usage"] = usage or "전체"

    print(f"  경매 {len(auction_items)}건 업로드 중...")
    auction_count = _batch_upload(db, "map_items", auction_items)

    # 실거래가 데이터 업로드
    for item in all_trades:
        item["_type"] = "trade"

    print(f"  실거래가 {len(all_trades)}건 업로드 중...")
    trade_count = _batch_upload(db, "map_items", all_trades)

    # 업로드 로그
    db.collection("upload_log").add({
        "command": "run",
        "court": court or "전체",
        "usage": usage or "전체",
        "year_month": year_month,
        "auction_count": auction_count,
        "trade_count": trade_count,
        "uploaded_at": firestore.SERVER_TIMESTAMP,
    })

    print(f"\n{'='*60}")
    print(f"  완료! 경매 {auction_count}건 + 실거래가 {trade_count}건 업로드됨")
    print(f"  Flutter 앱에서 지도를 열면 데이터가 표시됩니다.")
    print(f"{'='*60}")


# ─────────────────────────────────────────────
#  개별 명령: trade, auction (기존 기능 유지)
# ─────────────────────────────────────────────

def cmd_trade(args):
    """실거래가 개별 업로드"""
    db = get_db()
    service_key = get_service_key()
    scraper = RealEstateScraper(service_key)

    trade_type = args.type
    region_code = args.region_code
    field_map = RENT_FIELDS if "전월세" in trade_type else TRADE_FIELDS

    region_name = region_code
    for r in search_region(region_code):
        region_name = f"{r[0]} {r[1]}"
        break

    if args.start and args.end:
        print(f"\n[크롤링] {region_name} / {trade_type} / {args.start}~{args.end}")
        df = scraper.get_multi_month(trade_type, region_code, args.start, args.end)
    else:
        ym = args.year_month or datetime.now().strftime("%Y%m")
        print(f"\n[크롤링] {region_name} / {trade_type} / {ym}")
        df = scraper._fetch(trade_type, region_code, ym, field_map)

    if df.empty:
        print("조회 결과가 없습니다.")
        return

    print(f"  → {len(df)}건 수집")
    docs = []
    for _, row in df.iterrows():
        doc = row.to_dict()
        doc["_region_code"] = region_code
        doc["_region_name"] = region_name
        doc["_trade_type"] = trade_type
        doc["_type"] = "trade"
        docs.append(doc)

    count = _batch_upload(db, "map_items", docs)
    print(f"  → {count}건 업로드 완료!")


def cmd_auction(args):
    """경매 개별 업로드"""
    db = get_db()
    scraper = AuctionScraper()

    court = args.court or None
    usage = args.usage or None
    keyword = args.keyword or None

    print(f"\n[크롤링] 경매 - 법원:{court or '전체'} / 용도:{usage or '전체'}")
    results = scraper.search(court_name=court, usage=usage, search_word=keyword)

    if not results:
        print("검색 결과가 없습니다.")
        return

    print(f"  → {len(results)}건 수집")
    for item in results:
        item["_type"] = "auction"
        item["_court"] = court or "전체"
        item["_usage"] = usage or "전체"

    count = _batch_upload(db, "map_items", results)
    print(f"  → {count}건 업로드 완료!")


def main():
    parser = argparse.ArgumentParser(
        description="경매+실거래가 크롤링 → 좌표변환 → Firestore 업로드",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 통합 실행 (경매 → 실거래가 매칭 → 좌표 → 업로드)
  python upload.py run --court 서울중앙 --usage 아파트
  python upload.py run --court 수원 --usage 아파트 --year-month 202502

  # 개별: 실거래가만
  python upload.py trade --region-code 11680 --year-month 202502

  # 개별: 경매만
  python upload.py auction --court 서울중앙 --usage 아파트
        """,
    )
    sub = parser.add_subparsers(dest="command")

    # run (통합)
    sp_run = sub.add_parser("run", help="통합: 경매→실거래가 매칭→좌표→업로드")
    sp_run.add_argument("--court", help="법원 (예: 서울중앙)")
    sp_run.add_argument("--usage", help="용도 (예: 아파트)")
    sp_run.add_argument("--keyword", help="소재지 검색어")
    sp_run.add_argument("--year-month", help="실거래가 조회 년월 YYYYMM (기본: 이번달)")
    sp_run.set_defaults(func=cmd_run)

    # trade
    sp_trade = sub.add_parser("trade", help="실거래가 개별 업로드")
    sp_trade.add_argument("--region-code", required=True)
    sp_trade.add_argument("--year-month")
    sp_trade.add_argument("--start")
    sp_trade.add_argument("--end")
    sp_trade.add_argument("--type", default="아파트매매")
    sp_trade.set_defaults(func=cmd_trade)

    # auction
    sp_auction = sub.add_parser("auction", help="경매 개별 업로드")
    sp_auction.add_argument("--court")
    sp_auction.add_argument("--usage")
    sp_auction.add_argument("--keyword")
    sp_auction.set_defaults(func=cmd_auction)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    args.func(args)


if __name__ == "__main__":
    main()
