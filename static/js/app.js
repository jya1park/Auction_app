// ===== 탭 전환 =====
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(`tab-${btn.dataset.tab}`).classList.add('active');
    });
});

// ===== 초기화 =====
(function init() {
    // 기본 년월 설정 (이번 달)
    const now = new Date();
    const ym = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    document.getElementById('year-month').value = ym;

    // 경매 법원/용도 목록 로드
    loadAuctionOptions();
})();

// ===== 지역 검색 =====
document.getElementById('btn-search-region').addEventListener('click', searchRegion);
document.getElementById('region-keyword').addEventListener('keydown', e => {
    if (e.key === 'Enter') searchRegion();
});

async function searchRegion() {
    const keyword = document.getElementById('region-keyword').value.trim();
    if (!keyword) return;

    try {
        const resp = await fetch(`/api/regions/search?keyword=${encodeURIComponent(keyword)}`);
        const data = await resp.json();

        const container = document.getElementById('region-results');
        if (data.length === 0) {
            container.innerHTML = '<div class="region-item">검색 결과가 없습니다</div>';
            container.style.display = 'block';
            return;
        }

        container.innerHTML = data.map(r =>
            `<div class="region-item" onclick="selectRegion('${r.sido} ${r.sigungu}', '${r.code}')">
                <span>${r.sido} ${r.sigungu}</span>
                <span class="code">${r.code}</span>
            </div>`
        ).join('');
        container.style.display = 'block';
    } catch (err) {
        console.error('지역 검색 오류:', err);
    }
}

function selectRegion(name, code) {
    document.getElementById('selected-region').value = name;
    document.getElementById('region-code').value = code;
    document.getElementById('region-results').style.display = 'none';
}

// ===== 실거래가 조회 =====
document.getElementById('btn-search-trade').addEventListener('click', searchTrade);

async function searchTrade() {
    const regionCode = document.getElementById('region-code').value;
    const yearMonthRaw = document.getElementById('year-month').value; // YYYY-MM
    const tradeType = document.getElementById('trade-type').value;

    if (!regionCode) {
        alert('지역을 먼저 검색하고 선택해주세요.');
        return;
    }
    if (!yearMonthRaw) {
        alert('조회 년월을 선택해주세요.');
        return;
    }

    const yearMonth = yearMonthRaw.replace('-', ''); // YYYYMM

    const loading = document.getElementById('trade-loading');
    const results = document.getElementById('trade-results');
    const countEl = document.getElementById('trade-count');

    loading.style.display = 'block';
    results.innerHTML = '';
    countEl.style.display = 'none';

    try {
        const url = `/api/trade?region_code=${regionCode}&year_month=${yearMonth}&type=${encodeURIComponent(tradeType)}`;
        const resp = await fetch(url);
        const data = await resp.json();

        loading.style.display = 'none';

        if (data.error) {
            results.innerHTML = `<div class="empty-state"><div class="icon">⚠️</div><p>${data.error}</p></div>`;
            return;
        }

        if (data.length === 0) {
            results.innerHTML = '<div class="empty-state"><div class="icon">📭</div><p>해당 기간의 거래 데이터가 없습니다</p></div>';
            return;
        }

        countEl.innerHTML = `총 <span>${data.length}</span>건`;
        countEl.style.display = 'block';

        const isRent = tradeType.includes('전월세');
        results.innerHTML = data.map(item => renderTradeCard(item, isRent)).join('');

    } catch (err) {
        loading.style.display = 'none';
        results.innerHTML = `<div class="empty-state"><div class="icon">❌</div><p>조회 중 오류가 발생했습니다</p></div>`;
        console.error('실거래가 조회 오류:', err);
    }
}

function renderTradeCard(item, isRent) {
    const name = item['아파트명'] || item['aptNm'] || '-';
    const dong = item['법정동'] || item['umdNm'] || '';
    const area = item['전용면적(㎡)'] || item['excluUseAr'] || '';
    const floor = item['층'] || item['floor'] || '';
    const year = item['년'] || item['dealYear'] || '';
    const month = item['월'] || item['dealMonth'] || '';
    const day = item['일'] || item['dealDay'] || '';
    const buildYear = item['건축년도'] || item['buildYear'] || '';

    let priceHtml;
    if (isRent) {
        const deposit = item['보증금(만원)'] || item['deposit'] || '-';
        const monthly = item['월세(만원)'] || item['monthlyRent'] || '0';
        priceHtml = monthly === '0'
            ? `<span class="price">전세 ${formatPrice(deposit)}</span>`
            : `<span class="price">보증금 ${formatPrice(deposit)} / 월세 ${formatPrice(monthly)}</span>`;
    } else {
        const price = item['거래금액(만원)'] || item['dealAmount'] || '-';
        priceHtml = `<span class="price">${formatPrice(price)}</span>`;
    }

    return `
    <div class="card">
        <div class="card-title">${name}</div>
        <div class="card-body">
            <div class="card-field card-full-row">${priceHtml}</div>
            <div class="card-field"><span class="label">법정동</span><span class="value">${dong}</span></div>
            <div class="card-field"><span class="label">전용면적</span><span class="value">${area}㎡</span></div>
            <div class="card-field"><span class="label">층</span><span class="value">${floor}층</span></div>
            <div class="card-field"><span class="label">거래일</span><span class="value">${year}.${month}.${day}</span></div>
            <div class="card-field"><span class="label">건축년도</span><span class="value">${buildYear}년</span></div>
        </div>
    </div>`;
}

function formatPrice(raw) {
    if (!raw || raw === '-') return '-';
    const num = parseInt(String(raw).replace(/,/g, '').trim(), 10);
    if (isNaN(num)) return raw;
    if (num >= 10000) {
        const억 = Math.floor(num / 10000);
        const 만 = num % 10000;
        return 만 > 0 ? `${억}억 ${만.toLocaleString()}만원` : `${억}억원`;
    }
    return `${num.toLocaleString()}만원`;
}

// ===== 경매 =====
async function loadAuctionOptions() {
    try {
        const [courtsResp, usagesResp] = await Promise.all([
            fetch('/api/auction/courts'),
            fetch('/api/auction/usages'),
        ]);
        const courts = await courtsResp.json();
        const usages = await usagesResp.json();

        const courtSelect = document.getElementById('auction-court');
        courts.forEach(c => {
            courtSelect.innerHTML += `<option value="${c}">${c}</option>`;
        });

        const usageSelect = document.getElementById('auction-usage');
        usages.forEach(u => {
            usageSelect.innerHTML += `<option value="${u}">${u}</option>`;
        });
    } catch (err) {
        console.error('경매 옵션 로드 실패:', err);
    }
}

document.getElementById('btn-search-auction').addEventListener('click', searchAuction);

async function searchAuction() {
    const court = document.getElementById('auction-court').value;
    const usage = document.getElementById('auction-usage').value;
    const keyword = document.getElementById('auction-keyword').value.trim();

    const loading = document.getElementById('auction-loading');
    const results = document.getElementById('auction-results');
    const countEl = document.getElementById('auction-count');

    loading.style.display = 'block';
    results.innerHTML = '';
    countEl.style.display = 'none';

    try {
        const params = new URLSearchParams();
        if (court) params.set('court', court);
        if (usage) params.set('usage', usage);
        if (keyword) params.set('keyword', keyword);

        const resp = await fetch(`/api/auction/search?${params}`);
        const data = await resp.json();

        loading.style.display = 'none';

        if (data.length === 0) {
            results.innerHTML = '<div class="empty-state"><div class="icon">🔍</div><p>검색 결과가 없습니다</p></div>';
            return;
        }

        countEl.innerHTML = `총 <span>${data.length}</span>건`;
        countEl.style.display = 'block';

        results.innerHTML = data.map(renderAuctionCard).join('');

    } catch (err) {
        loading.style.display = 'none';
        results.innerHTML = `<div class="empty-state"><div class="icon">❌</div><p>경매 조회 중 오류가 발생했습니다</p></div>`;
        console.error('경매 조회 오류:', err);
    }
}

function renderAuctionCard(item) {
    return `
    <div class="card auction-card">
        <div class="card-title">${item['사건번호'] || '-'}</div>
        <div class="card-body">
            <div class="card-field card-full-row">
                <span class="label">소재지</span><span class="value">${item['소재지'] || '-'}</span>
            </div>
            <div class="card-field"><span class="label">물건종류</span><span class="value">${item['물건종류'] || '-'}</span></div>
            <div class="card-field"><span class="label">상태</span><span class="auction-status">${item['상태'] || '-'}</span></div>
            <div class="card-field"><span class="label">감정가</span><span class="value price">${item['감정가'] || '-'}</span></div>
            <div class="card-field"><span class="label">최저매각가</span><span class="value price">${item['최저매각가'] || '-'}</span></div>
            <div class="card-field card-full-row"><span class="label">매각기일</span><span class="value">${item['매각기일'] || '-'}</span></div>
        </div>
    </div>`;
}

// ===== 서비스워커 등록 =====
if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/static/sw.js').catch(err => {
        console.log('SW 등록 실패:', err);
    });
}
