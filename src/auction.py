"""
법원 경매정보 스크래퍼
- 대한민국 법원 경매정보(courtauction.go.kr)에서 경매 물건 조회
"""

import requests
from bs4 import BeautifulSoup


# 법원 코드 매핑
COURT_CODES = {
    "서울중앙": "B000100", "서울동부": "B000200", "서울서부": "B000300",
    "서울남부": "B000400", "서울북부": "B000500", "의정부": "B000600",
    "인천": "B000700", "수원": "B000800", "춘천": "B000900",
    "대전": "B001000", "청주": "B001100", "대구": "B001200",
    "부산": "B001300", "울산": "B001400", "창원": "B001500",
    "광주": "B001600", "전주": "B001700", "제주": "B001800",
    "고양": "B001900", "부천": "B002000", "성남": "B002100",
    "안산": "B002200", "안양": "B002300", "여주": "B002400",
    "평택": "B002500", "남양주": "B002600", "원주": "B002700",
    "강릉": "B002800", "속초": "B002900", "영월": "B003000",
    "논산": "B003100", "서산": "B003200", "천안": "B003300",
    "홍성": "B003400", "공주": "B003500", "영동": "B003600",
    "제천": "B003700", "충주": "B003800", "경주": "B003900",
    "김천": "B004000", "상주": "B004100", "의성": "B004200",
    "안동": "B004300", "영덕": "B004400", "포항": "B004500",
    "거창": "B004600", "밀양": "B004700", "진주": "B004800",
    "통영": "B004900", "김해": "B005000", "순천": "B005100",
    "목포": "B005200", "장흥": "B005300", "해남": "B005400",
    "군산": "B005500", "남원": "B005600", "정읍": "B005700",
    "김포": "B005800", "동해": "B005900", "서귀포": "B006000",
    "구미": "B006100", "양산": "B006200",
}

# 용도 코드
USAGE_CODES = {
    "아파트": "0001", "오피스텔": "0002", "다세대": "0003",
    "다가구": "0004", "단독주택": "0005", "근린시설": "0006",
    "토지": "0007", "상가": "0008", "공장": "0009",
}

COURT_AUCTION_URL = "https://www.courtauction.go.kr"


class AuctionScraper:
    """법원 경매 정보 스크래퍼"""

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Referer": COURT_AUCTION_URL,
        })

    def search(
        self,
        court_name: str | None = None,
        usage: str | None = None,
        search_word: str | None = None,
    ) -> list[dict]:
        """
        경매 물건 검색

        Args:
            court_name: 법원 이름 (예: "서울중앙")
            usage: 용도 (예: "아파트")
            search_word: 검색어 (소재지 등)
        """
        url = f"{COURT_AUCTION_URL}/RetrieveRealEstMulDetailList.laf"

        params = {
            "page": "1",
            "pageSize": "20",
            "targetRow": "1",
            "srnID": "PNO102001",
            "termStartDt": "",
            "termEndDt": "",
            "lclsUtilCd": "",
            "mclsUtilCd": "",
            "sclsUtilCd": "",
            "sidoCode": "",
            "sggCode": "",
            "realVowel": "",
            "notifyLoc": "",
            "srchJdgNm": "",
            "mnmRslAmt": "",
            "mxmRslAmt": "",
            "mnmApslAmt": "",
            "mxmApslAmt": "",
            "mnmAreaMtSq": "",
            "mxmAreaMtSq": "",
            "idsUtilCd": "",
            "srchDongNm": "",
        }

        if court_name and court_name in COURT_CODES:
            params["jiwonNm"] = COURT_CODES[court_name]

        if usage and usage in USAGE_CODES:
            params["lclsUtilCd"] = USAGE_CODES[usage]

        if search_word:
            params["srchDongNm"] = search_word

        try:
            resp = self.session.get(url, params=params, timeout=15)
            resp.raise_for_status()
            return self._parse_list(resp.text)
        except requests.RequestException as e:
            print(f"[오류] 경매 조회 실패: {e}")
            return []

    def _parse_list(self, html: str) -> list[dict]:
        """경매 물건 목록 HTML 파싱"""
        soup = BeautifulSoup(html, "lxml")
        results = []

        table = soup.select_one("table.Ltbl_list")
        if not table:
            return results

        rows = table.select("tbody tr")
        current_item = {}

        for row in rows:
            cells = row.select("td")
            if not cells:
                continue

            # 메인 행 (사건번호가 있는 행)
            if len(cells) >= 6:
                text_values = [c.get_text(strip=True) for c in cells]

                # 사건번호가 있는 새로운 물건
                if text_values[0] and "타경" in text_values[0]:
                    if current_item:
                        results.append(current_item)

                    current_item = {
                        "사건번호": text_values[0] if len(text_values) > 0 else "",
                        "물건종류": text_values[1] if len(text_values) > 1 else "",
                        "소재지": text_values[2] if len(text_values) > 2 else "",
                        "감정가": text_values[3] if len(text_values) > 3 else "",
                        "최저매각가": text_values[4] if len(text_values) > 4 else "",
                        "매각기일": text_values[5] if len(text_values) > 5 else "",
                        "상태": text_values[6] if len(text_values) > 6 else "",
                    }

        if current_item:
            results.append(current_item)

        return results

    @staticmethod
    def list_courts() -> list[str]:
        """법원 목록 반환"""
        return list(COURT_CODES.keys())

    @staticmethod
    def list_usages() -> list[str]:
        """용도 목록 반환"""
        return list(USAGE_CODES.keys())
