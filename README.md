# 부동산 경매 조회 앱 (Oh! Happy Day)

경매 물건 조회 + 실거래가 비교 + AI 세금 상담 + 단지 분석을 제공하는 Flutter 앱입니다.

## 주요 기능

### 1. 지도 (Map)
- 카카오맵 기반 경매 물건 마커 표시
- 경매중(파랑) / 낙찰(초록) / 유찰(주황) 필터
- 마커 클릭 시 물건 상세 팝업
- 실거래가 표시: 경매 물건과 **비슷한 면적** 우선 매칭

### 2. 목록 (List)
- 전체/경매중/낙찰/유찰 필터 칩
- **검색 기능**: 아파트명, 주소, 동명, 사건번호로 실시간 검색
- 검색 + 필터 동시 적용 가능

### 3. AI 세금 상담
- FAB 버튼 또는 물건 상세에서 "세금 상담" 클릭
- **LLM 라우터**: 질문에 맞는 세법 문서 1개 자동 선택
- **RAG**: 취득세/양도소득세/경매절차/주택임대차보호법 4개 문서
- **Dart 계산기**: 취득세/양도세/총비용 정확 계산 (GPT가 직접 계산하지 않음)
- **조정대상지역 자동 판별**: 물건 주소 → JSON 매칭 → 중과세율 적용
- **스트리밍 응답**: 글자 단위 실시간 표시 (ChatGPT 방식)
- **대화 히스토리**: 후속 질문 맥락 유지

### 4. 단지 분석
- 물건 상세에서 "단지 분석 (장점/단점)" 클릭
- **네이버 검색 API**: 실거주 후기(4건) + 하자(2건) + 임장 후기(4건) 검색
- **광고 필터링**: 인테리어 시공업체 광고 자동 제거
- GPT가 아파트 자체를 거주 관점에서 평가
- 긍정적 피드백 5개 + 부정적 피드백 5개
- **분석 근거 링크**: 네이버 블로그 원문 링크 제공
- 스트리밍 + 진행 상태 실시간 표시

### 5. 경매정보 보기
- 물건 상세에서 "경매정보 보기" 클릭
- 앱 내 WebView로 대법원 경매정보 사이트 열기
- **법원 + 년도 + 사건번호 자동 입력 + 검색 자동 클릭**

---

## 프로젝트 구조

```
Auction_app/
├── flutter_app/                    # Flutter 앱
│   ├── lib/
│   │   ├── main.dart              # 앱 진입점 (dotenv, Firebase 초기화)
│   │   ├── screens/
│   │   │   ├── home_screen.dart   # 홈 (지도/목록 탭 + AI FAB)
│   │   │   ├── map_screen.dart    # 카카오맵 WebView
│   │   │   ├── list_screen.dart   # 경매 목록 + 검색
│   │   │   └── tax_chat_screen.dart # AI 세금 상담 채팅
│   │   ├── services/
│   │   │   ├── openai_service.dart      # OpenAI API (라우터 + 스트리밍 + RAG)
│   │   │   ├── tax_calculator.dart      # Dart 세금 계산기
│   │   │   ├── naver_search_service.dart # 네이버 검색 + 블로그 크롤링
│   │   │   └── firestore_service.dart   # Firestore 데이터 조회
│   │   └── widgets/
│   │       ├── detail_sheet.dart   # 물건 상세 + 경매정보 + 단지 분석
│   │       ├── chat_bubble.dart    # 채팅 말풍선 + 타이핑 인디케이터
│   │       └── auction_card.dart   # 목록 카드
│   ├── assets/
│   │   ├── kakao_map.html         # 카카오맵 HTML
│   │   └── tax_knowledge/         # RAG 지식 베이스
│   │       ├── 00_index.json      # 키워드 → 문서 매핑
│   │       ├── 01_취득세.md
│   │       ├── 02_양도소득세.md
│   │       ├── 03_경매절차.md
│   │       ├── 04_주택임대차보호법.md
│   │       └── 05_조정대상지역.json
│   ├── .env                       # API 키 (git 제외)
│   └── .env.example               # API 키 템플릿
│
├── src/                           # Python 백엔드 (데이터 업로드)
│   ├── csv_parser.py              # CSV/XLSX 파서
│   ├── geocoder.py                # Kakao API 좌표 변환
│   ├── scraper.py                 # 실거래가 API 조회
│   └── matcher.py                 # 주소 → 지역코드 매칭
│
├── upload_csv.py                  # Firestore 업로드 스크립트
├── run_daily_upload.bat           # Windows 자동화 배치
└── firebase-key.json              # Firebase 인증 (git 제외)
```

---

## AI 시스템 아키텍처

### 세금 상담 흐름
```
사용자 질문
    ↓
① LLM 라우터 (API 1회)
   → 4개 세법 문서 중 1개 선택
    ↓
② 시스템 프롬프트 조립
   역할 + RAG 문서(1500자) + 물건 정보 + 조정대상지역 세율 + Dart 계산 결과
    ↓
③ 스트리밍 API 호출 (SSE)
   → 글자 단위 실시간 표시
```

### 단지 분석 흐름
```
"단지 분석" 클릭
    ↓
① 네이버 검색 API 3회
   실거주 후기(4건) + 하자(2건) + 임장(4건) = 최대 10건
    ↓
② 광고 필터링
   시공문의/견적/협찬 등 14개 키워드 → 2개 이상 포함 시 제거
    ↓
③ GPT 스트리밍 호출
   아파트명 + 주소만 전달 → 긍정/부정 피드백 각 5개
    ↓
④ 분석 근거 링크 표시
   네이버 블로그 원문 링크 (클릭 시 브라우저 열기)
```

---

## 설정

### .env 파일 (flutter_app/.env)
```
OPENAI_API_KEY=sk-proj-...
NAVER_CLIENT_ID=...
NAVER_CLIENT_SECRET=...
```

### API 키 발급

| API | 발급처 | 용도 |
|-----|--------|------|
| OpenAI | [platform.openai.com](https://platform.openai.com) | AI 세금 상담 + 단지 분석 |
| Naver 검색 | [developers.naver.com](https://developers.naver.com) | 단지 분석 블로그 검색 |
| Kakao 지도 | [developers.kakao.com](https://developers.kakao.com) | 지도 표시 + 좌표 변환 |

---

## 빌드 및 실행

### Flutter 앱
```bash
cd flutter_app
flutter clean
flutter pub get
flutter run
```

### 데이터 업로드
```bash
# xlsx 파일 (권장)
python upload_csv.py "C:\...\courtauction_data.xlsx" --clear

# CSV 파일
python upload_csv.py courtauction_result.csv --list-csv courtauction_list.csv --clear
```

### 자동화 (Windows 작업 스케줄러)
1. `Win+R` → `taskschd.msc`
2. 작업 만들기 → 매일 오전 8:30
3. 프로그램: `run_daily_upload.bat`
4. xlsx 파일 우선, 없으면 CSV 사용

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| 프론트엔드 | Flutter (Dart), Material 3 |
| 지도 | Kakao Maps JavaScript SDK (WebView) |
| 백엔드 | Firebase Firestore |
| AI | OpenAI GPT API (스트리밍 SSE) |
| RAG | 로컬 마크다운 파일 + LLM 라우터 |
| 검색 | Naver Blog Search API |
| 데이터 | Python (openpyxl, 공공데이터 API) |
