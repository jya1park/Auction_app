"""
courtauction_result.csv 파서
- jya1park/auction 리포에서 생성된 경매 CSV를 읽고 파싱

CSV 컬럼:
  전체, 사건번호, 물건번호, 소재지 및 내역, 비고, 감정평가액,
  담당계매각기일(입찰기간), 법원, 감정평가액_원, 용도, 매각결과, 매각금액, 매각금액_원

소재지 예시:
  "경기도 용인시 수지구 상현로 2 4704동 5층501호 (상현동,광교상현마을현대아파트)[집합건물 철근콘크리트조벽식구조 79.336㎡]"
"""

import csv
import re


def parse_location(raw: str) -> dict:
    """
    소재지 및 내역 문자열에서 개별 필드 추출

    Returns: {
        "주소": str,         # 괄호 앞의 도로명/지번 주소
        "동명": str,         # 법정동 (괄호 안 첫번째)
        "아파트명": str,      # 건물명 (괄호 안 두번째)
        "건물구조": str,      # 대괄호 안 구조 설명
        "전용면적": float,    # 면적 (㎡)
    }
    """
    result = {"주소": "", "동명": "", "아파트명": "", "건물구조": "", "전용면적": 0.0}

    # 줄바꿈 제거
    text = raw.replace("\n", " ").strip()

    # 1) 대괄호 [ ... ] 추출 (건물구조 + 면적)
    bracket_match = re.search(r'\[([^\]]+)\]', text)
    if bracket_match:
        bracket_content = bracket_match.group(1).strip()
        # 면적 추출: "79.336㎡", "84.9716 ㎡"
        area_match = re.search(r'(\d+\.?\d*)\s*㎡', bracket_content)
        if area_match:
            result["전용면적"] = float(area_match.group(1))
            # 건물구조 = 대괄호 내용에서 면적 부분 제거
            structure = re.sub(r'\s*\d+\.?\d*\s*㎡', '', bracket_content).strip()
            result["건물구조"] = structure
        else:
            result["건물구조"] = bracket_content
        # 대괄호 제거
        text = text[:bracket_match.start()].strip()

    # 2) 괄호 ( ... ) 추출 (법정동, 아파트명)
    paren_match = re.search(r'\(([^)]+)\)', text)
    if paren_match:
        paren_content = paren_match.group(1).strip()
        # "상현동,광교상현마을현대아파트" 형태
        parts = [p.strip() for p in paren_content.split(",")]
        if len(parts) >= 2:
            result["동명"] = parts[0]
            result["아파트명"] = parts[1]
        elif len(parts) == 1:
            # 쉼표 없는 경우, 동 이름이면 동명으로, 아니면 아파트명
            if parts[0].endswith("동") or parts[0].endswith("읍") or parts[0].endswith("면"):
                result["동명"] = parts[0]
            else:
                result["아파트명"] = parts[0]
        # 괄호 제거
        text = text[:paren_match.start()].strip()

    # 3) 남은 텍스트가 주소
    result["주소"] = text

    return result


def parse_sale_date(raw: str) -> str:
    """
    '경매14계2026.04.10' 형태에서 날짜만 추출
    Returns: "2026-04-10"
    """
    match = re.search(r'(\d{4})\.(\d{2})\.(\d{2})', raw)
    if match:
        return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"
    return ""


def parse_sale_month(raw: str) -> str:
    """매각기일에서 년월 추출 (YYYYMM)"""
    match = re.search(r'(\d{4})\.(\d{2})', raw)
    if match:
        return f"{match.group(1)}{match.group(2)}"
    return ""


def _to_int(val: str) -> int:
    """문자열 금액을 정수로 (쉼표 제거)"""
    if not val:
        return 0
    cleaned = str(val).replace(",", "").strip()
    try:
        return int(cleaned)
    except (ValueError, TypeError):
        return 0


def parse_csv(csv_path: str) -> list[dict]:
    """
    CSV 파일 파싱

    Returns: 각 행을 딕셔너리로 변환한 리스트
    """
    results = []

    # BOM 처리를 위해 utf-8-sig 사용
    with open(csv_path, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_location = row.get("소재지 및 내역", "")
            parsed_loc = parse_location(raw_location)

            sale_date_raw = row.get("담당계매각기일(입찰기간)", "")
            sale_date = parse_sale_date(sale_date_raw)
            sale_ym = parse_sale_month(sale_date_raw)

            appraisal = _to_int(row.get("감정평가액_원") or row.get("감정평가액"))
            sale_amount = _to_int(row.get("매각금액_원") or row.get("매각금액"))
            sale_result = row.get("매각결과", "").strip()

            # 할인율 계산 (매각금액 / 감정가)
            discount_ratio = 0.0
            if sale_amount > 0 and appraisal > 0:
                discount_ratio = round(sale_amount / appraisal * 100, 1)

            item = {
                "사건번호": row.get("사건번호", "").strip(),
                "물건번호": row.get("물건번호", "").strip(),
                "법원": row.get("법원", "").strip(),
                "용도": row.get("용도", "").strip(),
                "소재지_원본": raw_location,
                "주소": parsed_loc["주소"],
                "동명": parsed_loc["동명"],
                "아파트명": parsed_loc["아파트명"],
                "건물구조": parsed_loc["건물구조"],
                "전용면적": parsed_loc["전용면적"],
                "감정가": appraisal,
                "매각결과": sale_result,
                "매각금액": sale_amount,
                "할인율": discount_ratio,
                "매각기일": sale_date,
                "매각년월": sale_ym,
                "비고": row.get("비고", "").strip(),
            }
            results.append(item)

    return results
