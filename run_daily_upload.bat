@echo off
REM 매일 오전 8시 30분에 실거래가 자동 업데이트
REM 사용법: 작업 스케줄러에 등록 (자세한 내용은 README_SCHEDULE.md)

REM ====== 설정 ======
set PROJECT_DIR=C:\Users\jya1p\Documents\Auction_app
set CSV_DIR=C:\Users\jya1p\Documents\courtauction_crawler\output
set RESULT_CSV=%CSV_DIR%\courtauction_result.csv
set LIST_CSV=%CSV_DIR%\courtauction_list.csv
set LOG_DIR=%PROJECT_DIR%\logs

REM ====== 로그 파일 (날짜별) ======
for /f "tokens=1-3 delims=- " %%a in ("%date%") do (
    set TODAY=%%a%%b%%c
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set LOG_FILE=%LOG_DIR%\upload_%TODAY%.log

REM ====== 실행 ======
echo ============================================ >> "%LOG_FILE%"
echo [%date% %time%] 자동 업로드 시작 >> "%LOG_FILE%"
echo ============================================ >> "%LOG_FILE%"

cd /d "%PROJECT_DIR%"

REM CSV 파일 존재 확인
if not exist "%RESULT_CSV%" (
    echo [오류] CSV 파일 없음: %RESULT_CSV% >> "%LOG_FILE%"
    exit /b 1
)

REM 실거래가 업데이트 (실거래가 매칭 + 좌표 변환 + Firestore 업로드)
python upload_csv.py "%RESULT_CSV%" --list-csv "%LIST_CSV%" --clear >> "%LOG_FILE%" 2>&1

if errorlevel 1 (
    echo [실패] %date% %time% >> "%LOG_FILE%"
    exit /b 1
)

echo ============================================ >> "%LOG_FILE%"
echo [%date% %time%] 완료 >> "%LOG_FILE%"
echo ============================================ >> "%LOG_FILE%"
