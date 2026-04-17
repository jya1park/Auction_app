"""
부동산 실거래가 크롤러 설정
"""

# 국토교통부 실거래가 API 엔드포인트 (apis.data.go.kr)
# NOTE: http를 사용해야 함 (https 사용 시 SSL 오류 발생 가능)
# 이전(폐지) URL: http://openapi.molit.go.kr/OpenAPI_ToolInstallPackage/service/rest/RTMSOBJSvc/...
_BASE = "http://apis.data.go.kr/1613000"
API_ENDPOINTS = {
    "아파트매매": f"{_BASE}/RTMSDataSvcAptTradeDev/getRTMSDataSvcAptTradeDev",
    "아파트전월세": f"{_BASE}/RTMSDataSvcAptRent/getRTMSDataSvcAptRent",
    "오피스텔매매": f"{_BASE}/RTMSDataSvcOffiTrade/getRTMSDataSvcOffiTrade",
    "오피스텔전월세": f"{_BASE}/RTMSDataSvcOffiRent/getRTMSDataSvcOffiRent",
    "연립다세대매매": f"{_BASE}/RTMSDataSvcRHTrade/getRTMSDataSvcRHTrade",
    "연립다세대전월세": f"{_BASE}/RTMSDataSvcRHRent/getRTMSDataSvcRHRent",
    "단독다가구매매": f"{_BASE}/RTMSDataSvcSHTrade/getRTMSDataSvcSHTrade",
    "단독다가구전월세": f"{_BASE}/RTMSDataSvcSHRent/getRTMSDataSvcSHRent",
}

# 매매 거래 응답 필드 매핑 (영문 XML 태그 → 한글 컬럼명)
TRADE_FIELDS = {
    "dealAmount": "거래금액(만원)",
    "dealingGbn": "거래유형",
    "buildYear": "건축년도",
    "dealYear": "년",
    "dealMonth": "월",
    "dealDay": "일",
    "umdNm": "법정동",
    "aptNm": "아파트명",
    "excluUseAr": "전용면적(㎡)",
    "jibun": "지번",
    "floor": "층",
    "aptDong": "동",
    "roadNm": "도로명",
    "sggCd": "시군구코드",
    "rgstDate": "등기일자",
    "buyerGbn": "매수자유형",
    "slerGbn": "매도자유형",
}

# 오피스텔 매매 필드 (offiNm을 아파트명 컬럼에 매핑해서 통일)
OFFICETEL_TRADE_FIELDS = {
    "dealAmount": "거래금액(만원)",
    "dealingGbn": "거래유형",
    "buildYear": "건축년도",
    "dealYear": "년",
    "dealMonth": "월",
    "dealDay": "일",
    "umdNm": "법정동",
    "offiNm": "아파트명",
    "excluUseAr": "전용면적(㎡)",
    "jibun": "지번",
    "floor": "층",
    "sggCd": "시군구코드",
    "rgstDate": "등기일자",
    "buyerGbn": "매수자유형",
    "slerGbn": "매도자유형",
}

# 전월세 거래 응답 필드 매핑
RENT_FIELDS = {
    "deposit": "보증금(만원)",
    "monthlyRent": "월세(만원)",
    "buildYear": "건축년도",
    "dealYear": "년",
    "dealMonth": "월",
    "dealDay": "일",
    "umdNm": "법정동",
    "aptNm": "아파트명",
    "excluUseAr": "전용면적(㎡)",
    "jibun": "지번",
    "floor": "층",
    "aptDong": "동",
    "sggCd": "시군구코드",
}

# 기본 설정
DEFAULT_NUM_OF_ROWS = 1000
DEFAULT_PAGE_NO = 1
