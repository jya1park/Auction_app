"""
주소 → 위경도 좌표 변환 (Geocoding)
- Kakao Local API 사용 (무료, 한국 주소 특화)

사전 준비:
  1. https://developers.kakao.com 가입
  2. 애플리케이션 추가 → REST API 키 복사
  3. .env 파일에 KAKAO_REST_API_KEY=your_key 추가
"""

import os
import time
from typing import Dict, List, Optional

import requests

_KAKAO_SEARCH_URL = "https://dapi.kakao.com/v2/local/search/address.json"
_KAKAO_KEYWORD_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"


def _get_kakao_key() -> str:
    key = os.environ.get("KAKAO_REST_API_KEY")
    if key:
        return key
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    if os.path.exists(env_path):
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("KAKAO_REST_API_KEY="):
                    return line.split("=", 1)[1].strip().strip("\"'")
    return ""


def geocode(address: str) -> Optional[Dict]:
    """
    주소를 위경도 좌표로 변환

    Returns: {"lat": float, "lng": float, "address": str} 또는 None
    """
    key = _get_kakao_key()
    if not key:
        return None

    headers = {"Authorization": f"KakaoAK {key}"}

    # 1차: 주소 검색
    try:
        resp = requests.get(
            _KAKAO_SEARCH_URL,
            headers=headers,
            params={"query": address},
            timeout=10,
        )
        data = resp.json()
        if data.get("documents"):
            doc = data["documents"][0]
            return {
                "lat": float(doc["y"]),
                "lng": float(doc["x"]),
                "address": doc.get("address_name", address),
            }
    except requests.RequestException:
        pass

    # 2차: 키워드 검색 (주소가 정확하지 않을 때)
    try:
        resp = requests.get(
            _KAKAO_KEYWORD_URL,
            headers=headers,
            params={"query": address},
            timeout=10,
        )
        data = resp.json()
        if data.get("documents"):
            doc = data["documents"][0]
            return {
                "lat": float(doc["y"]),
                "lng": float(doc["x"]),
                "address": doc.get("address_name", address),
            }
    except requests.RequestException:
        pass

    return None


def batch_geocode(addresses: List[str], delay: float = 0.2) -> List[Optional[Dict]]:
    """여러 주소를 일괄 변환 (API rate limit 고려)"""
    results = []
    for i, addr in enumerate(addresses):
        result = geocode(addr)
        results.append(result)
        if i < len(addresses) - 1:
            time.sleep(delay)
    return results
