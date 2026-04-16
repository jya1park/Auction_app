#!/usr/bin/env python3
"""
크롤링 데이터를 Google Firestore에 업로드하는 스크립트

사전 준비:
  1. Firebase 콘솔(https://console.firebase.google.com)에서 프로젝트 생성
  2. Firestore Database 활성화 (테스트 모드로 시작)
  3. 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성 → JSON 파일 다운로드
  4. 다운로드한 JSON 파일을 이 프로젝트 루트에 'firebase-key.json'으로 저장

사용법:
  # 실거래가 업로드 (단일 월)
  python upload.py trade --region-code 11680 --year-month 202502

  # 실거래가 업로드 (기간)
  python upload.py trade --region-code 11680 --start 202501 --end 202506

  # 경매 데이터 업로드
  python upload.py auction --court 서울중앙 --usage 아파트
"""

import argparse
import os
import sys
from datetime import datetime

from google.cloud import firestore

from src.auction import AuctionScraper
from src.config import API_ENDPOINTS, RENT_FIELDS, TRADE_FIELDS
from src.region_code import search_region
from src.scraper import RealEstateScraper

FIREBASE_KEY_PATH = os.path.join(os.path.dirname(__file__), "firebase-key.json")


def get_db() -> firestore.Client:
    """Firestore 클라이언트 생성"""
    if not os.path.exists(FIREBASE_KEY_PATH):
        print("=" * 60)
        print("[오류] firebase-key.json 파일이 없습니다.")
        print()
        print("설정 방법:")
        print("  1. https://console.firebase.google.com 접속")
        print("  2. 프로젝트 생성 (또는 기존 프로젝트 선택)")
        print("  3. Firestore Database → 데이터베이스 만들기")
        print("  4. 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성")
        print("  5. 다운로드한 JSON을 프로젝트 루트에 firebase-key.json으로 저장")
        print("=" * 60)
        sys.exit(1)

    return firestore.Client.from_service_account_json(FIREBASE_KEY_PATH)


def get_service_key() -> str:
    """data.go.kr API 키 로드"""
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


def upload_trade(args):
    """실거래가 크롤링 후 Firestore 업로드"""
    db = get_db()
    service_key = get_service_key()
    scraper = RealEstateScraper(service_key)

    trade_type = args.type
    region_code = args.region_code

    if trade_type not in API_ENDPOINTS:
        print(f"[오류] 지원하지 않는 거래유형: {trade_type}")
        sys.exit(1)

    field_map = RENT_FIELDS if "전월세" in trade_type else TRADE_FIELDS

    # 지역명 조회
    region_name = region_code
    for sido_districts in search_region(region_code):
        region_name = f"{sido_districts[0]} {sido_districts[1]}"
        break

    # 데이터 수집
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

    print(f"  → {len(df)}건 수집 완료")

    # Firestore 업로드
    print(f"[업로드] Firestore에 업로드 중...")
    collection = db.collection("trades")
    batch = db.batch()
    count = 0

    for _, row in df.iterrows():
        doc_data = row.to_dict()
        # 메타 정보 추가
        doc_data["_region_code"] = region_code
        doc_data["_region_name"] = region_name
        doc_data["_trade_type"] = trade_type
        doc_data["_uploaded_at"] = firestore.SERVER_TIMESTAMP

        doc_ref = collection.document()
        batch.set(doc_ref, doc_data)
        count += 1

        # Firestore batch는 500건 제한
        if count % 400 == 0:
            batch.commit()
            batch = db.batch()
            print(f"  → {count}건 업로드됨...")

    if count % 400 != 0:
        batch.commit()

    # 업로드 기록 저장
    db.collection("upload_log").add({
        "type": "trade",
        "trade_type": trade_type,
        "region_code": region_code,
        "region_name": region_name,
        "count": count,
        "uploaded_at": firestore.SERVER_TIMESTAMP,
    })

    print(f"  → 총 {count}건 업로드 완료!")


def upload_auction(args):
    """경매 데이터 크롤링 후 Firestore 업로드"""
    db = get_db()
    scraper = AuctionScraper()

    court = args.court or None
    usage = args.usage or None
    keyword = args.keyword or None

    print(f"\n[크롤링] 경매 검색 - 법원:{court or '전체'} / 용도:{usage or '전체'} / 키워드:{keyword or '없음'}")
    results = scraper.search(court_name=court, usage=usage, search_word=keyword)

    if not results:
        print("검색 결과가 없습니다.")
        return

    print(f"  → {len(results)}건 수집 완료")

    # Firestore 업로드
    print("[업로드] Firestore에 업로드 중...")
    collection = db.collection("auctions")
    batch = db.batch()

    for i, item in enumerate(results):
        item["_court"] = court or "전체"
        item["_usage"] = usage or "전체"
        item["_uploaded_at"] = firestore.SERVER_TIMESTAMP

        doc_ref = collection.document()
        batch.set(doc_ref, item)

        if (i + 1) % 400 == 0:
            batch.commit()
            batch = db.batch()

    batch.commit()

    db.collection("upload_log").add({
        "type": "auction",
        "court": court or "전체",
        "usage": usage or "전체",
        "count": len(results),
        "uploaded_at": firestore.SERVER_TIMESTAMP,
    })

    print(f"  → 총 {len(results)}건 업로드 완료!")


def main():
    parser = argparse.ArgumentParser(
        description="크롤링 → Firestore 업로드",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 실거래가 (단일 월)
  python upload.py trade --region-code 11680 --year-month 202502

  # 실거래가 (기간)
  python upload.py trade --region-code 11680 --start 202501 --end 202506 --type 아파트매매

  # 경매
  python upload.py auction --court 서울중앙 --usage 아파트
  python upload.py auction --keyword 역삼동
        """,
    )
    sub = parser.add_subparsers(dest="command")

    # trade
    sp_trade = sub.add_parser("trade", help="실거래가 크롤링 → 업로드")
    sp_trade.add_argument("--region-code", required=True, help="법정동코드 5자리")
    sp_trade.add_argument("--year-month", help="조회 년월 YYYYMM")
    sp_trade.add_argument("--start", help="시작 년월 YYYYMM")
    sp_trade.add_argument("--end", help="종료 년월 YYYYMM")
    sp_trade.add_argument("--type", default="아파트매매", help="거래유형 (기본: 아파트매매)")
    sp_trade.set_defaults(func=upload_trade)

    # auction
    sp_auction = sub.add_parser("auction", help="경매 크롤링 → 업로드")
    sp_auction.add_argument("--court", help="법원 (예: 서울중앙)")
    sp_auction.add_argument("--usage", help="용도 (예: 아파트)")
    sp_auction.add_argument("--keyword", help="소재지 검색어")
    sp_auction.set_defaults(func=upload_auction)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    args.func(args)


if __name__ == "__main__":
    main()
