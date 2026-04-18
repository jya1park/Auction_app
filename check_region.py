#!/usr/bin/env python3
"""
data.go.kr 실거래가 API 단일 지역 진단
- 특정 시군구 코드로 직접 호출해서 응답 확인
- 0건 반환 시 코드가 잘못됐는지, API 권한 문제인지 판단

사용법:
  python check_region.py 41590         # 화성시 진단
  python check_region.py 41590 202602  # 특정 월 지정
  python check_region.py 41117 202602 오피스텔   # 오피스텔 API
"""

import os
import sys
import xml.etree.ElementTree as ET
from urllib.parse import urlencode

import requests


def read_env_key(name="DATA_GO_KR_API_KEY"):
    key = os.environ.get(name)
    if key:
        return key
    env = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if os.path.exists(env):
        with open(env, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                if k.strip() == name:
                    return v.strip().strip('"\'').strip()
    return ""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    lawd_cd = sys.argv[1]
    deal_ymd = sys.argv[2] if len(sys.argv) > 2 else "202602"
    api_type = sys.argv[3] if len(sys.argv) > 3 else "아파트"

    if api_type == "오피스텔":
        url = "http://apis.data.go.kr/1613000/RTMSDataSvcOffiTrade/getRTMSDataSvcOffiTrade"
    else:
        url = "http://apis.data.go.kr/1613000/RTMSDataSvcAptTradeDev/getRTMSDataSvcAptTradeDev"

    key = read_env_key()
    if not key:
        print("[오류] DATA_GO_KR_API_KEY 없음")
        sys.exit(1)

    params = {
        "serviceKey": key,
        "LAWD_CD": lawd_cd,
        "DEAL_YMD": deal_ymd,
        "pageNo": 1,
        "numOfRows": 10,
    }

    print(f"[요청] {api_type} API")
    print(f"  LAWD_CD = {lawd_cd}")
    print(f"  DEAL_YMD = {deal_ymd}")
    print(f"  URL = {url}?{urlencode(params)[:100]}...")
    print()

    resp = requests.get(url, params=params, timeout=30)
    print(f"[응답] status = {resp.status_code}")
    print(f"[응답 내용 앞 1500자]")
    print(resp.text[:1500])
    print()

    if resp.status_code != 200:
        sys.exit(1)

    try:
        root = ET.fromstring(resp.text)
    except ET.ParseError as e:
        print(f"[오류] XML 파싱 실패: {e}")
        sys.exit(1)

    result_code = root.findtext(".//resultCode")
    result_msg = root.findtext(".//resultMsg")
    total_count = root.findtext(".//totalCount")
    items = root.findall(".//item")

    print(f"[결과]")
    print(f"  resultCode = {result_code}")
    print(f"  resultMsg = {result_msg}")
    print(f"  totalCount = {total_count}")
    print(f"  items 갯수 = {len(items)}")

    if items:
        print(f"\n[샘플 거래 1건]")
        first = items[0]
        for child in first:
            print(f"  {child.tag} = {child.text}")
    elif result_code in ("00", "000"):
        print()
        print("⚠ API는 정상 응답했지만 거래 0건")
        print("  가능성:")
        print("  1) 해당 월에 실제로 거래 없음 (시도해볼 다른 월: 202509, 202410)")
        print("  2) 시군구 코드가 다르게 분할되어 있음 (예: 신도시는 다른 코드)")
        print(f"  3) {api_type} API에 해당 지역 데이터 미등록")


if __name__ == "__main__":
    main()
