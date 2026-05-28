@echo off
chcp 65001 >nul
REM ============================================================
REM 매일 오전 8시 자동 파이프라인:
REM   1) auction 리포에서 크롤링 (courtauction_data.xlsx 생성)
REM   2) Auction_app에서 Firestore로 업로드
REM 사용법: 작업 스케줄러에 등록
REM ============================================================

REM ====== 경로 설정 (본인 환경에 맞게 수정) ======
set CRAWLER_DIR=C:\Users\jya1p\Documents\courtauction_crawler
set UPLOADER_DIR=C:\Users\jya1p\Documents\Auction_app
set XLSX_FILE=%CRAWLER_DIR%\output\courtauction_data.xlsx

REM 크롤러는 시스템 Python 사용 (또는 venv 경로로 변경)
set CRAWLER_PY=python
REM 업로더는 Auction_app의 venv 사용 (Firestore SDK가 그쪽에 설치됨)
set UPLOADER_PY=%UPLOADER_DIR%\venv\Scripts\python.exe

REM ====== 로그 파일 (날짜별) ======
set LOG_DIR=%UPLOADER_DIR%\logs
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
for /f "tokens=1-3 delims=- " %%a in ("%date%") do set TODAY=%%a%%b%%c
set LOG_FILE=%LOG_DIR%\daily_%TODAY%.log

echo ============================================ >> "%LOG_FILE%"
echo [%date% %time%] 자동 파이프라인 시작 >> "%LOG_FILE%"
echo ============================================ >> "%LOG_FILE%"

REM ========== 1단계: 크롤링 ==========
echo. >> "%LOG_FILE%"
echo [%date% %time%] === 1/2 크롤링 시작 === >> "%LOG_FILE%"
cd /d "%CRAWLER_DIR%"
%CRAWLER_PY% main.py >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%date% %time%] [FAIL] 크롤링 실패 - 종료 >> "%LOG_FILE%"
    exit /b 1
)
echo [%date% %time%] [OK] 크롤링 완료 >> "%LOG_FILE%"

REM ========== 2단계: 업로드 ==========
if not exist "%XLSX_FILE%" (
    echo [%date% %time%] [FAIL] XLSX 파일 없음: %XLSX_FILE% >> "%LOG_FILE%"
    exit /b 1
)
if not exist "%UPLOADER_PY%" (
    echo [%date% %time%] [FAIL] 업로더 venv 없음: %UPLOADER_PY% >> "%LOG_FILE%"
    echo [안내] py -3.12 -m venv venv 으로 생성 >> "%LOG_FILE%"
    exit /b 1
)

echo. >> "%LOG_FILE%"
echo [%date% %time%] === 2/2 Firestore 업로드 시작 === >> "%LOG_FILE%"
cd /d "%UPLOADER_DIR%"
"%UPLOADER_PY%" upload_csv.py "%XLSX_FILE%" --clear >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%date% %time%] [FAIL] 업로드 실패 >> "%LOG_FILE%"
    exit /b 1
)
echo [%date% %time%] [OK] 업로드 완료 >> "%LOG_FILE%"

echo. >> "%LOG_FILE%"
echo ============================================ >> "%LOG_FILE%"
echo [%date% %time%] 전체 파이프라인 완료 >> "%LOG_FILE%"
echo ============================================ >> "%LOG_FILE%"
