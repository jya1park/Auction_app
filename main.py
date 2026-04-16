#!/usr/bin/env python3
"""
부동산 실거래가 크롤러 CLI
- 주소(시군구)를 입력하면 국토교통부 실거래가 API에서 데이터를 수집합니다.

사용법:
  python main.py --help
  python main.py search 강남
  python main.py crawl --region-code 11680 --year-month 202403
  python main.py crawl --region-code 11680 --start 202401 --end 202412 --type 아파트매매
"""

import argparse
import os
import sys
from datetime import datetime

import pandas as pd

from src.region_code import list_all_sido, list_sigungu, search_region
from src.scraper import RealEstateScraper
from src.config import API_ENDPOINTS

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")


def get_service_key() -> str:
    """환경변수 또는 .env 파일에서 API 키 로드"""
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

    print("=" * 60)
    print("[안내] API 키가 설정되지 않았습니다.")
    print()
    print("data.go.kr에서 '국토교통부_아파트매매 실거래 상세 자료'")
    print("API를 신청하고, 발급받은 디코딩 키를 설정해주세요.")
    print()
    print("설정 방법 (택 1):")
    print("  1. 환경변수: export DATA_GO_KR_API_KEY='your_key'")
    print("  2. .env 파일: 프로젝트 루트에 .env 파일 생성")
    print("     DATA_GO_KR_API_KEY=your_key")
    print("=" * 60)
    sys.exit(1)


def cmd_search(args):
    """지역 검색 명령"""
    results = search_region(args.keyword)
    if not results:
        print(f"'{args.keyword}'에 해당하는 지역을 찾을 수 없습니다.")
        return

    print(f"\n'{args.keyword}' 검색 결과 ({len(results)}건):")
    print("-" * 50)
    print(f"{'시/도':<15} {'시군구':<15} {'코드':<10}")
    print("-" * 50)
    for sido, district, code in results:
        print(f"{sido:<15} {district:<15} {code:<10}")
    print()
    print("조회 예시:")
    if results:
        code = results[0][2]
        print(f"  python main.py crawl --region-code {code} --year-month 202403")


def cmd_list(args):
    """지역 목록 명령"""
    if args.sido:
        districts = list_sigungu(args.sido)
        if not districts:
            print(f"'{args.sido}'에 해당하는 시/도를 찾을 수 없습니다.")
            all_sido = list_all_sido()
            print(f"사용 가능한 시/도: {', '.join(all_sido)}")
            return

        print(f"\n[{args.sido}] 시군구 목록:")
        print("-" * 40)
        for name, code in districts:
            print(f"  {name:<20} {code}")
    else:
        sido_list = list_all_sido()
        print("\n시/도 목록:")
        print("-" * 30)
        for s in sido_list:
            print(f"  {s}")
        print()
        print("시군구 보기: python main.py list --sido 서울특별시")


def cmd_crawl(args):
    """크롤링 실행 명령"""
    service_key = get_service_key()
    scraper = RealEstateScraper(service_key)

    trade_type = args.type
    lawd_cd = args.region_code

    if trade_type not in API_ENDPOINTS:
        print(f"[오류] 지원하지 않는 거래유형: {trade_type}")
        print(f"사용 가능: {', '.join(API_ENDPOINTS.keys())}")
        sys.exit(1)

    # 단일 월 조회 vs 기간 조회
    if args.year_month:
        print(f"\n[조회] 지역코드: {lawd_cd}, 거래유형: {trade_type}, 기간: {args.year_month}")
        df = scraper._fetch(trade_type, lawd_cd, args.year_month,
                            _get_field_map(trade_type))
    elif args.start and args.end:
        print(f"\n[조회] 지역코드: {lawd_cd}, 거래유형: {trade_type}, 기간: {args.start}~{args.end}")
        df = scraper.get_multi_month(trade_type, lawd_cd, args.start, args.end)
    else:
        # 기본: 현재 월
        now = datetime.now()
        ym = f"{now.year:04d}{now.month:02d}"
        print(f"\n[조회] 지역코드: {lawd_cd}, 거래유형: {trade_type}, 기간: {ym}")
        df = scraper._fetch(trade_type, lawd_cd, ym, _get_field_map(trade_type))

    if df.empty:
        print("\n조회 결과가 없습니다.")
        return

    # 결과 출력
    print(f"\n총 {len(df)}건 조회됨")
    print("=" * 80)

    # 매매가의 경우 금액 정렬
    if "거래금액(만원)" in df.columns:
        df["_정렬용금액"] = df["거래금액(만원)"].str.replace(",", "").str.strip()
        df["_정렬용금액"] = pd.to_numeric(df["_정렬용금액"], errors="coerce")
        df = df.sort_values("_정렬용금액", ascending=False).drop(columns=["_정렬용금액"])

    pd.set_option("display.max_rows", None)
    pd.set_option("display.max_columns", None)
    pd.set_option("display.width", 120)
    pd.set_option("display.max_colwidth", 20)
    print(df.to_string(index=False))

    # CSV 저장
    if args.save:
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{trade_type}_{lawd_cd}_{timestamp}.csv"
        filepath = os.path.join(OUTPUT_DIR, filename)
        df.to_csv(filepath, index=False, encoding="utf-8-sig")
        print(f"\n[저장 완료] {filepath}")


def _get_field_map(trade_type: str) -> dict:
    from src.config import RENT_FIELDS, TRADE_FIELDS
    return RENT_FIELDS if "전월세" in trade_type else TRADE_FIELDS


def cmd_types(_args):
    """지원 거래유형 목록"""
    print("\n지원하는 거래유형:")
    print("-" * 30)
    for name in API_ENDPOINTS:
        print(f"  {name}")


def main():
    parser = argparse.ArgumentParser(
        description="부동산 실거래가 크롤러 - 국토교통부 공공데이터 API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 지역 검색
  python main.py search 강남
  python main.py search 분당

  # 지역 목록 보기
  python main.py list
  python main.py list --sido 서울특별시

  # 거래유형 보기
  python main.py types

  # 실거래가 조회 (단일 월)
  python main.py crawl --region-code 11680 --year-month 202403

  # 실거래가 조회 (기간)
  python main.py crawl --region-code 11680 --start 202401 --end 202412 --type 아파트매매

  # CSV 저장
  python main.py crawl --region-code 11680 --year-month 202403 --save
        """,
    )
    subparsers = parser.add_subparsers(dest="command", help="명령어")

    # search 명령
    sp_search = subparsers.add_parser("search", help="지역 검색 (예: search 강남)")
    sp_search.add_argument("keyword", help="검색할 지역 키워드")
    sp_search.set_defaults(func=cmd_search)

    # list 명령
    sp_list = subparsers.add_parser("list", help="지역 목록 보기")
    sp_list.add_argument("--sido", help="시/도 이름 (예: 서울특별시)")
    sp_list.set_defaults(func=cmd_list)

    # types 명령
    sp_types = subparsers.add_parser("types", help="지원 거래유형 보기")
    sp_types.set_defaults(func=cmd_types)

    # crawl 명령
    sp_crawl = subparsers.add_parser("crawl", help="실거래가 크롤링")
    sp_crawl.add_argument(
        "--region-code", required=True, help="법정동코드 5자리 (search 명령으로 조회)"
    )
    sp_crawl.add_argument("--year-month", help="조회 년월 YYYYMM (예: 202403)")
    sp_crawl.add_argument("--start", help="시작 년월 YYYYMM (기간 조회)")
    sp_crawl.add_argument("--end", help="종료 년월 YYYYMM (기간 조회)")
    sp_crawl.add_argument(
        "--type", default="아파트매매", help="거래유형 (기본: 아파트매매)"
    )
    sp_crawl.add_argument(
        "--save", action="store_true", help="결과를 CSV 파일로 저장"
    )
    sp_crawl.set_defaults(func=cmd_crawl)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(0)

    args.func(args)


if __name__ == "__main__":
    main()
