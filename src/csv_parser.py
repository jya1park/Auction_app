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
from typing import Dict, List


def parse_location(raw):
    # type: (str) -> Dict
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
    result = {"주소": "", "동명": "", "아파트명": "", "건물구조": "", "전용면적": 0.0,
              "본번": 0, "부번": 0}

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

    # 3) 괄호가 없거나 아파트명을 못 찾은 경우, 주소에서 추출 시도
    #    예: "경기도 수원시 영통구 하동 1001 광교 더 포레스트 4008동 25층2501호"
    #         → 아파트명: "광교 더 포레스트"
    if not result["아파트명"] and text:
        extracted = _extract_apt_from_address(text)
        if extracted:
            result["아파트명"] = extracted

    # 4) 남은 텍스트가 주소
    result["주소"] = text

    # 5) 주소에서 지번 본번/부번 추출
    #    "동 985" → 본번=985, 부번=0
    #    "동 103-11" → 본번=103, 부번=11
    #    도로명도 시도: "로 406" → 본번=406
    jibun_match = re.search(r'[동읍면리]\s+(\d+)(?:-(\d+))?\s', text + " ")
    if jibun_match:
        result["본번"] = int(jibun_match.group(1))
        result["부번"] = int(jibun_match.group(2) or 0)

    return result


def _extract_apt_from_address(address):
    """
    소재지 문자열에서 아파트명 추출 (괄호 없이 임베드된 경우)

    패턴1: ... 지번 [아파트명] N동 N층NNN호
      예: "하동 1001 광교 더 포레스트 4008동 25층2501호" → "광교 더 포레스트"
    패턴2: ... 지번 [아파트명] (주소 끝, 동번호 없음)
      예: "신봉동 985 신봉마을동일하이빌3단지" → "신봉마을동일하이빌3단지"
    패턴3: ... 도로명 번호 [아파트명] N층NNN호
      예: "경수대로 406 파크앤시티타워2 8층801호" → "파크앤시티타워2"
    """
    # 패턴1: "지번 [아파트명] N동" (동번호 있는 경우)
    m = re.search(
        r'(?:\d+(?:-\d+)?)\s+([가-힣A-Za-z0-9\s·\']+?)\s+\d+동\s',
        address + " ",
    )
    if m:
        candidate = m.group(1).strip()
        if _is_valid_apt_name(candidate):
            return candidate

    # 패턴2: "법정동 지번 [아파트명]" (동번호 없이 주소 끝)
    m = re.search(
        r'[동읍면리]\s+\d+(?:-\d+)?\s+(.+?)$',
        address.strip(),
    )
    if m:
        candidate = m.group(1).strip()
        candidate = re.sub(r'\s*\d+동\s*\d+층.*$', '', candidate).strip()
        candidate = re.sub(r'\s*\d+층.*$', '', candidate).strip()
        candidate = re.sub(r'\s*\d+호$', '', candidate).strip()
        if _is_valid_apt_name(candidate):
            return candidate

    # 패턴3: "도로명 번호 [아파트명] N동/N층" (도로명 주소, 아파트명이 한글로 시작)
    m = re.search(
        r'(?:로|길)\s+\d+(?:-\d+)?\s+([가-힣][가-힣A-Za-z0-9\s·\']+?)(?:\s+\d+동|\s+\d+층|$)',
        address.strip(),
    )
    if m:
        candidate = m.group(1).strip()
        if _is_valid_apt_name(candidate):
            return candidate

    return ""


def _is_valid_apt_name(name):
    """아파트명 후보가 유효한지 확인"""
    if not name or len(name) < 2:
        return False
    if name.replace(' ', '').isdigit():
        return False
    if re.match(r'^[가-힣]+[동읍면리]$', name):
        return False
    return True


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


def parse_csv(csv_path):
    # type: (str) -> List[Dict]
    """
    courtauction_result.csv 파싱 (경매 결과)
    """
    results = []
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

            discount_ratio = 0.0
            if sale_amount > 0 and appraisal > 0:
                discount_ratio = round(sale_amount / appraisal * 100, 1)

            # 매각결과를 3분류로 통일: 낙찰/유찰/경매중
            if sale_result == "매각":
                status = "낙찰"
            elif sale_result == "유찰":
                status = "유찰"
            else:
                status = "경매중"

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
                "본번": parsed_loc["본번"],
                "부번": parsed_loc["부번"],
                "감정가": appraisal,
                "최저입찰가": 0,
                "매각결과": sale_result,
                "경매상태": status,
                "매각금액": sale_amount,
                "할인율": discount_ratio,
                "매각기일": sale_date,
                "매각년월": sale_ym,
                "유찰횟수": 0,
                "비고": row.get("비고", "").strip(),
            }
            results.append(item)

    return results


def parse_list_csv(csv_path):
    # type: (str) -> List[Dict]
    """
    courtauction_list.csv 파싱 (경매 진행중)

    컬럼: 사건번호, 법원, 물건번호, 물건주소, 용도, 비고, 감정평가액,
          감정가_원, 입찰기일, 유찰횟수_입찰란, 링크, 진행상태,
          최저입찰가_표시, 최저입찰가_원, 최저입찰가율, 유찰횟수, 유찰횟수_원문
    """
    results = []
    with open(csv_path, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_location = row.get("물건주소", "")
            parsed_loc = parse_location(raw_location)

            bid_date_raw = row.get("입찰기일", "")
            bid_date = parse_sale_date(bid_date_raw)
            bid_ym = parse_sale_month(bid_date_raw)

            appraisal = _to_int(row.get("감정가_원") or row.get("감정평가액"))
            min_bid = _to_int(row.get("최저입찰가_원", ""))

            try:
                fail_count = int(row.get("유찰횟수", 0) or 0)
            except (ValueError, TypeError):
                fail_count = 0

            # 최저입찰가율
            try:
                bid_rate = float(row.get("최저입찰가율", 0) or 0)
            except (ValueError, TypeError):
                bid_rate = 0.0

            usage = row.get("진행상태", "").strip()
            fail_text = row.get("유찰횟수_원문", "").strip()

            item = {
                "사건번호": row.get("사건번호", "").strip(),
                "물건번호": row.get("물건번호", "").strip(),
                "법원": row.get("법원", "").strip(),
                "용도": usage if usage else "아파트",
                "소재지_원본": raw_location,
                "주소": parsed_loc["주소"],
                "동명": parsed_loc["동명"],
                "아파트명": parsed_loc["아파트명"],
                "건물구조": parsed_loc["건물구조"],
                "전용면적": parsed_loc["전용면적"],
                "본번": parsed_loc["본번"],
                "부번": parsed_loc["부번"],
                "감정가": appraisal,
                "최저입찰가": min_bid,
                "최저입찰가율": bid_rate,
                "매각결과": "",
                "경매상태": "경매중",
                "매각금액": 0,
                "할인율": 0.0,
                "매각기일": bid_date,
                "매각년월": bid_ym,
                "유찰횟수": fail_count,
                "유찰횟수_원문": fail_text,
                "비고": row.get("비고", "").strip(),
            }
            results.append(item)

    return results


def parse_xlsx(xlsx_path):
    # type: (str) -> List[Dict]
    """
    courtauction_data.xlsx 파싱 (경매목록 + 매각결과 시트)
    """
    import openpyxl

    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    results = []

    # 매각결과 시트
    result_sheet = None
    for name in wb.sheetnames:
        if '매각' in name or '결과' in name:
            result_sheet = wb[name]
            break

    if result_sheet:
        rows = list(result_sheet.iter_rows(values_only=True))
        if rows:
            headers = [str(h or '').strip() for h in rows[0]]
            for row in rows[1:]:
                r = {headers[i]: (row[i] if i < len(row) else '') for i in range(len(headers))}

                raw_location = str(r.get('소재지 및 내역', '') or '')
                parsed_loc = parse_location(raw_location)

                full_text = str(r.get('전체', '') or '')
                court = ''
                court_match = re.match(r'([가-힣]+(?:지방)?법원)', full_text)
                if court_match:
                    court = court_match.group(1)

                sale_date_raw = str(r.get('담당계매각기일(입찰기간)', '') or '')
                sale_date = parse_sale_date(sale_date_raw)
                sale_ym = parse_sale_month(sale_date_raw)

                appraisal = _to_int(r.get('감정평가액_원') or r.get('감정평가액'))
                sale_amount = _to_int(r.get('매각금액_원') or r.get('매각금액'))
                sale_result = str(r.get('매각결과', '') or '').strip()

                discount_ratio = 0.0
                if sale_amount > 0 and appraisal > 0:
                    discount_ratio = round(sale_amount / appraisal * 100, 1)

                if sale_result == '매각':
                    status = '낙찰'
                elif sale_result == '유찰':
                    status = '유찰'
                else:
                    status = '경매중'

                item = {
                    '사건번호': str(r.get('사건번호', '') or '').strip(),
                    '물건번호': str(r.get('물건번호', '') or '').strip(),
                    '법원': court,
                    '용도': str(r.get('용도', '') or '').strip(),
                    '소재지_원본': raw_location,
                    '주소': parsed_loc['주소'],
                    '동명': parsed_loc['동명'],
                    '아파트명': parsed_loc['아파트명'],
                    '건물구조': parsed_loc['건물구조'],
                    '전용면적': parsed_loc['전용면적'],
                    '본번': parsed_loc['본번'],
                    '부번': parsed_loc['부번'],
                    '감정가': appraisal,
                    '최저입찰가': 0,
                    '매각결과': sale_result,
                    '경매상태': status,
                    '매각금액': sale_amount,
                    '할인율': discount_ratio,
                    '매각기일': sale_date,
                    '매각년월': sale_ym,
                    '유찰횟수': 0,
                    '비고': str(r.get('비고', '') or '').strip(),
                }
                results.append(item)

    # 경매목록 시트
    list_sheet = None
    for name in wb.sheetnames:
        if '목록' in name:
            list_sheet = wb[name]
            break

    if list_sheet:
        rows = list(list_sheet.iter_rows(values_only=True))
        if rows:
            headers = [str(h or '').strip() for h in rows[0]]
            for row in rows[1:]:
                r = {headers[i]: (row[i] if i < len(row) else '') for i in range(len(headers))}

                raw_location = str(r.get('물건주소', '') or '')
                parsed_loc = parse_location(raw_location)

                bid_date_raw = str(r.get('입찰기일', '') or '')
                bid_date = parse_sale_date(bid_date_raw)
                bid_ym = parse_sale_month(bid_date_raw)

                appraisal = _to_int(r.get('감정가_원') or r.get('감정평가액'))
                min_bid = _to_int(r.get('최저입찰가_원', ''))

                try:
                    fail_count = int(r.get('유찰횟수', 0) or 0)
                except (ValueError, TypeError):
                    fail_count = 0

                try:
                    bid_rate = float(r.get('최저입찰가율', 0) or 0)
                except (ValueError, TypeError):
                    bid_rate = 0.0

                usage = str(r.get('진행상태', '') or '').strip()
                fail_text = str(r.get('유찰횟수_원문', '') or '').strip()

                item = {
                    '사건번호': str(r.get('사건번호', '') or '').strip(),
                    '물건번호': str(r.get('물건번호', '') or '').strip(),
                    '법원': str(r.get('법원', '') or '').strip(),
                    '용도': usage if usage else '아파트',
                    '소재지_원본': raw_location,
                    '주소': parsed_loc['주소'],
                    '동명': parsed_loc['동명'],
                    '아파트명': parsed_loc['아파트명'],
                    '건물구조': parsed_loc['건물구조'],
                    '전용면적': parsed_loc['전용면적'],
                    '본번': parsed_loc['본번'],
                    '부번': parsed_loc['부번'],
                    '감정가': appraisal,
                    '최저입찰가': min_bid,
                    '최저입찰가율': bid_rate,
                    '매각결과': '',
                    '경매상태': '경매중',
                    '매각금액': 0,
                    '할인율': 0.0,
                    '매각기일': bid_date,
                    '매각년월': bid_ym,
                    '유찰횟수': fail_count,
                    '유찰횟수_원문': fail_text,
                    '비고': str(r.get('비고', '') or '').strip(),
                }
                results.append(item)

    wb.close()
    return results
