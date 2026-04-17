"""
법정동코드 검색 모듈
- 주소 키워드로 시군구 코드(5자리)를 조회
"""

import json
import os
from typing import Dict, List, Optional, Tuple

DATA_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "region_codes.json")


def load_region_codes() -> Dict:
    """region_codes.json 로드"""
    with open(DATA_PATH, encoding="utf-8") as f:
        return json.load(f)


def search_region(keyword: str) -> List[Tuple[str, str, str]]:
    """
    키워드로 지역 검색.
    Returns: [(시도, 시군구, 코드), ...]
    """
    data = load_region_codes()
    results = []
    keyword = keyword.strip()

    for sido, districts in data.items():
        for district, code in districts.items():
            if keyword in sido or keyword in district:
                results.append((sido, district, code))

    return results


def get_region_code(sido: str, sigungu: str) -> Optional[str]:
    """정확한 시도+시군구 이름으로 코드 조회"""
    data = load_region_codes()
    if sido in data and sigungu in data[sido]:
        return data[sido][sigungu]
    return None


def list_all_sido() -> List[str]:
    """모든 시/도 목록 반환"""
    data = load_region_codes()
    return list(data.keys())


def list_sigungu(sido: str) -> List[Tuple[str, str]]:
    """특정 시/도의 시군구 목록 반환: [(시군구명, 코드), ...]"""
    data = load_region_codes()
    if sido not in data:
        return []
    return [(name, code) for name, code in data[sido].items()]
