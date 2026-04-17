"""
국토교통부 실거래가 API 크롤러
- data.go.kr 공공데이터 API를 호출하여 실거래가 데이터를 수집
"""

import time
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional

import pandas as pd
import requests

from src.config import (
    API_ENDPOINTS,
    DEFAULT_NUM_OF_ROWS,
    DEFAULT_PAGE_NO,
    RENT_FIELDS,
    TRADE_FIELDS,
)


class RealEstateScraper:
    """부동산 실거래가 크롤러"""

    def __init__(self, service_key: str, debug: bool = False):
        """
        Args:
            service_key: data.go.kr에서 발급받은 인증키 (디코딩된 키)
            debug: True이면 API 응답 원본 출력
        """
        self.service_key = service_key
        self.debug = debug

    def _call_api(self, url: str, lawd_cd: str, deal_ymd: str) -> Optional[str]:
        """API 호출 후 XML 텍스트 반환"""
        params = {
            "serviceKey": self.service_key,
            "LAWD_CD": lawd_cd,
            "DEAL_YMD": deal_ymd,
            "pageNo": DEFAULT_PAGE_NO,
            "numOfRows": DEFAULT_NUM_OF_ROWS,
        }

        try:
            resp = requests.get(url, params=params, timeout=30)
            resp.raise_for_status()
            if self.debug:
                print(f"[DEBUG] URL: {resp.url}")
                print(f"[DEBUG] Status: {resp.status_code}")
                print(f"[DEBUG] 응답 앞 1000자:\n{resp.text[:1000]}")
            return resp.text
        except requests.RequestException as e:
            print(f"[오류] API 호출 실패: {e}")
            return None

    def _parse_xml(self, xml_text: str, field_map: dict) -> List[Dict]:
        """XML 응답을 파싱하여 딕셔너리 리스트로 변환"""
        try:
            root = ET.fromstring(xml_text)
        except ET.ParseError as e:
            print(f"[오류] XML 파싱 실패: {e}")
            return []

        # 에러 응답 확인 (정상 코드: "00", "000")
        result_code = root.findtext(".//resultCode")
        if result_code and result_code not in ("00", "000"):
            result_msg = root.findtext(".//resultMsg", "알 수 없는 오류")
            print(f"[오류] API 에러 (코드: {result_code}): {result_msg}")
            return []

        items = root.findall(".//item")
        if self.debug and items:
            first = items[0]
            tags = [child.tag for child in first]
            print(f"[DEBUG] XML 필드 목록: {tags}")

        results = []

        for item in items:
            row = {}
            # 매핑된 필드 추출
            for xml_tag, col_name in field_map.items():
                elem = item.find(xml_tag)
                value = elem.text.strip() if elem is not None and elem.text else ""
                row[col_name] = value
            # 매핑에 없는 필드도 원본 태그명으로 포함
            for child in item:
                if child.tag not in field_map and child.text:
                    row[child.tag] = child.text.strip()
            results.append(row)

        return results

    def get_apt_trade(
        self, lawd_cd: str, deal_ymd: str
    ) -> pd.DataFrame:
        """아파트 매매 실거래가 조회"""
        return self._fetch("아파트매매", lawd_cd, deal_ymd, TRADE_FIELDS)

    def get_apt_rent(
        self, lawd_cd: str, deal_ymd: str
    ) -> pd.DataFrame:
        """아파트 전월세 실거래가 조회"""
        return self._fetch("아파트전월세", lawd_cd, deal_ymd, RENT_FIELDS)

    def get_officetel_trade(
        self, lawd_cd: str, deal_ymd: str
    ) -> pd.DataFrame:
        """오피스텔 매매 실거래가 조회"""
        return self._fetch("오피스텔매매", lawd_cd, deal_ymd, TRADE_FIELDS)

    def get_officetel_rent(
        self, lawd_cd: str, deal_ymd: str
    ) -> pd.DataFrame:
        """오피스텔 전월세 실거래가 조회"""
        return self._fetch("오피스텔전월세", lawd_cd, deal_ymd, RENT_FIELDS)

    def get_row_house_trade(
        self, lawd_cd: str, deal_ymd: str
    ) -> pd.DataFrame:
        """연립다세대 매매 실거래가 조회"""
        return self._fetch("연립다세대매매", lawd_cd, deal_ymd, TRADE_FIELDS)

    def get_row_house_rent(
        self, lawd_cd: str, deal_ymd: str
    ) -> pd.DataFrame:
        """연립다세대 전월세 실거래가 조회"""
        return self._fetch("연립다세대전월세", lawd_cd, deal_ymd, RENT_FIELDS)

    def get_detached_trade(
        self, lawd_cd: str, deal_ymd: str
    ) -> pd.DataFrame:
        """단독/다가구 매매 실거래가 조회"""
        return self._fetch("단독다가구매매", lawd_cd, deal_ymd, TRADE_FIELDS)

    def get_detached_rent(
        self, lawd_cd: str, deal_ymd: str
    ) -> pd.DataFrame:
        """단독/다가구 전월세 실거래가 조회"""
        return self._fetch("단독다가구전월세", lawd_cd, deal_ymd, RENT_FIELDS)

    def _fetch(
        self, trade_type: str, lawd_cd: str, deal_ymd: str, field_map: dict
    ) -> pd.DataFrame:
        """공통 조회 로직"""
        url = API_ENDPOINTS[trade_type]
        xml_text = self._call_api(url, lawd_cd, deal_ymd)
        if xml_text is None:
            return pd.DataFrame()

        rows = self._parse_xml(xml_text, field_map)
        if not rows:
            return pd.DataFrame()

        df = pd.DataFrame(rows)
        return df

    def get_multi_month(
        self,
        trade_type: str,
        lawd_cd: str,
        start_ymd: str,
        end_ymd: str,
        delay: float = 0.5,
    ) -> pd.DataFrame:
        """
        여러 달의 데이터를 한번에 조회

        Args:
            trade_type: 거래 유형 (예: "아파트매매", "아파트전월세")
            lawd_cd: 법정동코드 5자리
            start_ymd: 시작 년월 (YYYYMM)
            end_ymd: 종료 년월 (YYYYMM)
            delay: API 호출 간 대기시간(초)
        """
        is_rent = "전월세" in trade_type
        field_map = RENT_FIELDS if is_rent else TRADE_FIELDS

        months = self._generate_months(start_ymd, end_ymd)
        all_dfs = []

        for i, ym in enumerate(months):
            print(f"  [{i + 1}/{len(months)}] {ym[:4]}년 {ym[4:]}월 조회 중...")
            df = self._fetch(trade_type, lawd_cd, ym, field_map)
            if not df.empty:
                all_dfs.append(df)
            if i < len(months) - 1:
                time.sleep(delay)

        if not all_dfs:
            return pd.DataFrame()

        return pd.concat(all_dfs, ignore_index=True)

    @staticmethod
    def _generate_months(start_ymd: str, end_ymd: str) -> List[str]:
        """시작~종료 년월 사이의 모든 YYYYMM 리스트 생성"""
        start_y, start_m = int(start_ymd[:4]), int(start_ymd[4:6])
        end_y, end_m = int(end_ymd[:4]), int(end_ymd[4:6])

        months = []
        y, m = start_y, start_m
        while (y, m) <= (end_y, end_m):
            months.append(f"{y:04d}{m:02d}")
            m += 1
            if m > 12:
                m = 1
                y += 1
        return months
