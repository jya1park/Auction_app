"""
부동산 실거래가 & 경매 정보 웹앱 (Flask)
"""

import os

from flask import Flask, jsonify, render_template, request
from flask_cors import CORS

from src.auction import AuctionScraper
from src.config import API_ENDPOINTS
from src.region_code import list_all_sido, list_sigungu, search_region
from src.scraper import RealEstateScraper

app = Flask(__name__)
CORS(app)


def _get_service_key() -> str:
    """API 키 로드"""
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
    return ""


# ─── 페이지 라우트 ───

@app.route("/")
def index():
    return render_template("index.html")


# ─── 실거래가 API ───

@app.route("/api/regions/search")
def api_search_region():
    """지역 검색"""
    keyword = request.args.get("keyword", "").strip()
    if not keyword:
        return jsonify({"error": "keyword 파라미터가 필요합니다"}), 400

    results = search_region(keyword)
    return jsonify([
        {"sido": r[0], "sigungu": r[1], "code": r[2]}
        for r in results
    ])


@app.route("/api/regions/sido")
def api_list_sido():
    """시/도 목록"""
    return jsonify(list_all_sido())


@app.route("/api/regions/sigungu")
def api_list_sigungu():
    """시군구 목록"""
    sido = request.args.get("sido", "")
    districts = list_sigungu(sido)
    return jsonify([{"name": d[0], "code": d[1]} for d in districts])


@app.route("/api/trade")
def api_trade():
    """실거래가 조회"""
    region_code = request.args.get("region_code", "")
    year_month = request.args.get("year_month", "")
    trade_type = request.args.get("type", "아파트매매")

    if not region_code or not year_month:
        return jsonify({"error": "region_code, year_month 필수"}), 400

    if trade_type not in API_ENDPOINTS:
        return jsonify({"error": f"지원하지 않는 거래유형: {trade_type}"}), 400

    service_key = _get_service_key()
    if not service_key:
        return jsonify({"error": "API 키가 설정되지 않았습니다"}), 500

    scraper = RealEstateScraper(service_key)
    from src.config import RENT_FIELDS, TRADE_FIELDS
    field_map = RENT_FIELDS if "전월세" in trade_type else TRADE_FIELDS
    df = scraper._fetch(trade_type, region_code, year_month, field_map)

    if df.empty:
        return jsonify([])

    return jsonify(df.to_dict(orient="records"))


@app.route("/api/trade/types")
def api_trade_types():
    """거래유형 목록"""
    return jsonify(list(API_ENDPOINTS.keys()))


# ─── 경매 API ───

@app.route("/api/auction/search")
def api_auction_search():
    """경매 물건 검색"""
    court = request.args.get("court", "")
    usage = request.args.get("usage", "")
    keyword = request.args.get("keyword", "")

    scraper = AuctionScraper()
    results = scraper.search(
        court_name=court or None,
        usage=usage or None,
        search_word=keyword or None,
    )
    return jsonify(results)


@app.route("/api/auction/courts")
def api_auction_courts():
    """법원 목록"""
    return jsonify(AuctionScraper.list_courts())


@app.route("/api/auction/usages")
def api_auction_usages():
    """용도 목록"""
    return jsonify(AuctionScraper.list_usages())


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
