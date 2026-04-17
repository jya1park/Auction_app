"""
경매 물건 → 실거래가 자동 매칭 모듈
- 경매 물건의 소재지에서 시군구를 추출
- 해당 시군구의 실거래가를 조회하여 매칭
"""

import json
import os
import re
from typing import Dict, Optional, Tuple

_REVERSE_MAP = {}  # type: Dict[str, Tuple[str, str]]  # "강남구" → ("서울특별시", "11680")


def _load_reverse_map():
    if _REVERSE_MAP:
        return
    data_path = os.path.join(os.path.dirname(__file__), "..", "data", "region_codes.json")
    with open(data_path, encoding="utf-8") as f:
        data = json.load(f)
    for sido, districts in data.items():
        for district, code in districts.items():
            # "강남구" → code, "성남시분당구" → code
            _REVERSE_MAP[district] = (sido, code)
            # 시 이름 없는 구 이름도 등록 (예: "분당구" → "성남시분당구")
            if "시" in district and "구" in district:
                gu_only = district[district.index("시") + 1:]
                if gu_only not in _REVERSE_MAP:
                    _REVERSE_MAP[gu_only] = (sido, code)


def extract_region_from_address(address: str) -> Optional[Tuple[str, str]]:
    """
    주소 문자열에서 시군구 코드를 추출

    Args:
        address: 경매 물건 소재지 (예: "서울특별시 강남구 역삼동 123-4")

    Returns: (시군구명, 법정동코드) 또는 None
    """
    _load_reverse_map()
    addr = address.strip()

    # 패턴 1: "OO시 OO구", "OO도 OO시", "OO도 OO군"
    patterns = [
        r'(\S+시\S+구)',      # 성남시분당구 (붙어있는 경우)
        r'(\S+구)',           # 강남구
        r'(\S+시)\s',         # 수원시 (뒤에 구가 없는 단독시)
        r'(\S+군)',           # 가평군
    ]

    for pattern in patterns:
        match = re.search(pattern, addr)
        if match:
            name = match.group(1)
            if name in _REVERSE_MAP:
                sido, code = _REVERSE_MAP[name]
                return (name, code)

    # 패턴 2: 역방향 매핑에서 주소에 포함된 키워드 직접 매칭
    for district, (sido, code) in _REVERSE_MAP.items():
        if district in addr:
            return (district, code)

    return None


def extract_dong_from_address(address: str) -> str:
    """주소에서 동/읍/면 이름 추출"""
    # "역삼동", "수내동" 등
    match = re.search(r'(\S+[동읍면리])\s', address + " ")
    if match:
        return match.group(1)
    return ""
