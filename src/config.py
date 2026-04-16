"""
부동산 실거래가 크롤러 설정
"""

# 국토교통부 실거래가 API 엔드포인트 (apis.data.go.kr)
_BASE = "https://apis.data.go.kr/1613000"
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

# 매매 거래 응답 필드 매핑
TRADE_FIELDS = {
    "거래금액": "거래금액(만원)",
    "거래유형": "거래유형",
    "건축년도": "건축년도",
    "년": "년",
    "월": "월",
    "일": "일",
    "법정동": "법정동",
    "아파트": "아파트명",
    "전용면적": "전용면적(㎡)",
    "지번": "지번",
    "층": "층",
    "해제여부": "해제여부",
    "해제사유발생일": "해제사유발생일",
}

# 전월세 거래 응답 필드 매핑
RENT_FIELDS = {
    "보증금액": "보증금(만원)",
    "월세금액": "월세(만원)",
    "건축년도": "건축년도",
    "년": "년",
    "월": "월",
    "일": "일",
    "법정동": "법정동",
    "아파트": "아파트명",
    "전용면적": "전용면적(㎡)",
    "지번": "지번",
    "층": "층",
}

# 기본 설정
DEFAULT_NUM_OF_ROWS = 1000
DEFAULT_PAGE_NO = 1
