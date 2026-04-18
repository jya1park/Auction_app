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

# 화성시 분구 매핑: 법정동 → 구 코드
_HWASEONG_DONG_MAP = {
    # 만세구 (41591)
    "새솔동": "41591",
    # 만세구 읍면
    "우정읍": "41591", "향남읍": "41591", "남양읍": "41591",
    "마도면": "41591", "송산면": "41591", "서신면": "41591",
    "팔탄면": "41591", "장안면": "41591", "양감면": "41591",
    # 만세구 리 (읍면 하위, 읍면으로 매칭 안 될 때 대비)
    "원안리": "41591", "호곡리": "41591", "운평리": "41591",
    "하길리": "41591", "발안리": "41591",
    # 효행구 (41593)
    "배양동": "41593", "기안동": "41593",
    "봉담읍": "41593", "매송면": "41593", "비봉면": "41593", "정남면": "41593",
    "동화리": "41593", "상리": "41593", "내리": "41593",
    # 병점구 (41595)
    "진안동": "41595", "병점동": "41595",
    "기산동": "41595", "반월동": "41595", "반정동": "41595",
    "황계동": "41595", "송산동": "41595", "안녕동": "41595",
    # 동탄구 (41597)
    "반송동": "41597", "석우동": "41597", "청계동": "41597",
    "영천동": "41597", "중동": "41597", "신동": "41597",
    "목동": "41597", "산척동": "41597", "장지동": "41597",
    "송동": "41597", "방교동": "41597", "금곡동": "41597",
    "여울동": "41597",
    # 병점구+동탄구 공통 (능동): 문맥으로 구분 필요, 기본=병점구
    "능동": "41595",
}


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

    # 화성시 분구 처리: 동 이름으로 병점구/동탄구 판별
    if "화성시" in addr:
        # 법정동 추출: 한글 2자+ 동/읍/면/리 (건물동 "103동" 제외)
        dong_matches = re.findall(r'([가-힣]+[동읍면리])[\s,)\]]', addr + " ")
        for dong in dong_matches:
            code = _HWASEONG_DONG_MAP.get(dong)
            if code:
                gu_names = {
                    "41591": "화성시만세구", "41593": "화성시효행구",
                    "41595": "화성시병점구", "41597": "화성시동탄구",
                }
                return (gu_names.get(code, "화성시"), code)
        # 동이 매핑에 없으면 기존 화성시 코드(41590) 사용
        return ("화성시", "41590")

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
