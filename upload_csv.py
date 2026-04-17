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

from src.config import TRADE_FIELDS
from src.csv_parser import parse_csv
from src.geocoder import geocode
from src.matcher import extract_region_from_address
from src.region_code import search_region
from src.scraper import RealEstateScraper

FIREBASE_KEY_PATH = os.path.join(os.path.dirname(__file__), "firebase-key.json")


def get_db():
    if not os.path.exists(FIREBASE_KEY_PATH):
        print("[오류] firebase-key.json 파일이 없습니다. 프로젝트 루트에 배치하세요.")
        sys.exit(1)
    return firestore.Client.from_service_account_json(FIREBASE_KEY_PATH)


def get_data_go_kr_key():
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    if os.path.exists(env_path):
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("DATA_GO_KR_API_KEY="):
                    return line.split("=", 1)[1].strip().strip("\"'")
    return os.environ.get("DATA_GO_KR_API_KEY", "")


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

    # 실거래가 매칭
    all_trades = []
    if not args.skip_trade and region_codes_found:
        print(f"\n{'='*60}")
        print(f"[3/4] 실거래가 매칭 ({len(region_codes_found)}개 지역)")
        print(f"{'='*60}")

        service_key = get_data_go_kr_key()
        if not service_key:
            print("  [경고] DATA_GO_KR_API_KEY가 없어 실거래가 매칭을 생략합니다")
        else:
            trade_scraper = RealEstateScraper(service_key)
            # 기준 월: 가장 많은 경매 건의 매각년월 중 이전달
            year_month = datetime.now().strftime("%Y%m")
            # 지난 달로 조회 (데이터 지연 고려)
            now = datetime.now()
            prev_month = now.month - 1 if now.month > 1 else 12
            prev_year = now.year if now.month > 1 else now.year - 1
            year_month = f"{prev_year:04d}{prev_month:02d}"

            print(f"  기준 월: {year_month}")

            for code in region_codes_found:
                region_name = code
                for r in search_region(code):
                    region_name = f"{r[0]} {r[1]}"
                    break

                print(f"  {region_name} ({code}) 조회 중...")
                df = trade_scraper._fetch("아파트매매", code, year_month, TRADE_FIELDS)

                if df.empty:
                    print(f"    → 0건")
                    continue

                print(f"    → {len(df)}건")

                for _, row in df.iterrows():
                    trade_data = row.to_dict()
                    trade_data["_region_code"] = code
                    trade_data["_region_name"] = region_name
                    trade_data["_trade_type"] = "아파트매매"
                    trade_data["_type"] = "trade"

                    # 좌표 변환
                    if not args.skip_geocode:
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
                        time.sleep(0.1)

                    all_trades.append(trade_data)

            print(f"  → 실거래가 총 {len(all_trades)}건")

    # Firestore 업로드
    print(f"\n{'='*60}")
    print(f"[4/4] Firestore 업로드")
    print(f"{'='*60}")

    db = get_db()

    # 경매 데이터 타입 지정
    for item in auction_items:
        item["_type"] = "auction"
        item["_source"] = "courtauction_csv"

    print(f"  경매 {len(auction_items)}건 업로드 중...")
    auction_count = batch_upload(db, "map_items", auction_items)

    if all_trades:
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
