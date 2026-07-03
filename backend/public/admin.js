// API 기본 URL
const API_BASE = '/api/admin';
const MARKET_API_BASE = '/api/admin/market';
const ADS_API_BASE = '/api/admin/ads';

// 페이지네이션 및 정렬 상태
let estimatesPage = 1;
const estimatesPerPage = 15;
let estimatesSortColumn = null;
let estimatesSortDirection = 'asc';
let allEstimates = [];

// 오더 현황 페이지네이션 및 정렬 상태
let callsPage = 1;
const callsPerPage = 15;
let callsSortColumn = null;
let callsSortDirection = 'asc';
let allCalls = [];

// 관리자 토큰 (.env 파일의 ADMIN_TOKEN과 일치해야 함)
const ADMIN_TOKEN = 'allsuri-admin-2024';
let ADMIN_ROLE = 'developer';

// 광고 편집 상태 (파일 최상단에 선언해야 TDZ 오류 방지)
let currentEditingAd = null;

// 공지 배너 (파일 최상단에 선언해야 TDZ 오류 방지)
let allAnnouncements = [];
let currentEditingAnnouncement = null;

// 웹 견적 관리 (파일 최상단에 선언해야 TDZ 오류 방지)
let allWebOrders = [];
let currentWebOrderId = null;
let selectedRating = 0;
let bizSearchTimer = null;

// 로그인 체크
function checkLogin() {
    const password = localStorage.getItem('admin_password');
    if (!password || password !== 'allsuri1912') {
        const inputPassword = prompt('관리자 비밀번호를 입력하세요:');
        if (!inputPassword || inputPassword !== 'allsuri1912') {
            alert('비밀번호가 틀렸습니다.');
            document.body.innerHTML = '<h1 style="text-align:center;margin-top:50px;">접근이 거부되었습니다.</h1>';
            return false;
        }
        localStorage.setItem('admin_password', inputPassword);
    }
    return true;
}

// API 호출 헬퍼 함수 테스트
async function apiCall(endpoint, options = {}) {
    const url = `${API_BASE}${endpoint}`;
    const config = {
        headers: {
            'Content-Type': 'application/json',
            'admin-token': ADMIN_TOKEN,
            ...options.headers
        },
        ...options
    };

    // 디버그 로그 추가
    console.log('[API CALL] URL:', url);
    console.log('[API CALL] Headers:', config.headers);
    console.log('[API CALL] Token being sent:', ADMIN_TOKEN);

    try {
        const response = await fetch(url, config);
        if (!response.ok) {
            let errorMessage = `HTTP error! status: ${response.status}`;
            try {
                const errorData = await response.json();
                console.error('[API CALL] Error response:', errorData);
                if (errorData.error) {
                    errorMessage += `\n에러: ${errorData.error}`;
                }
                if (errorData.details) {
                    errorMessage += `\n상세: ${errorData.details}`;
                }
                if (errorData.message) {
                    errorMessage += `\n메시지: ${errorData.message}`;
                }
            } catch (e) {
                console.error('[API CALL] Could not parse error response');
            }
            if (response.status === 401) {
                throw new Error('관리자 권한이 필요합니다. ADMIN_TOKEN을 확인해주세요.');
            }
            throw new Error(errorMessage);
        }
        return await response.json();
    } catch (error) {
        console.error('API 호출 오류:', error);
        throw error;
    }
}

        // 대시보드 데이터 로드
        async function loadDashboard() {
            try {
                await loadAdminMe();
                const data = await apiCall('/dashboard');
                
                console.log('[DASHBOARD] ===== 받은 데이터 상세 =====');
                console.log('[DASHBOARD] 전체 데이터:', JSON.stringify(data, null, 2));
                console.log('[DASHBOARD] totalOrders:', data.totalOrders);
                console.log('[DASHBOARD] pendingOrders:', data.pendingOrders);
                console.log('[DASHBOARD] completedOrders:', data.completedOrders);
                console.log('[DASHBOARD] totalEstimates:', data.totalEstimates);
                console.log('[DASHBOARD] ================================');
                
                // 사용자 통계
                const totalBusinessUsers = data.totalBusinessUsers || 0;
                const totalCustomers = data.totalCustomers || 0;
                
                const totalBusinessUsersEl = document.getElementById('totalBusinessUsers');
                if (totalBusinessUsersEl) totalBusinessUsersEl.textContent = totalBusinessUsers;
                
                const totalCustomersEl = document.getElementById('totalCustomers');
                if (totalCustomersEl) totalCustomersEl.textContent = totalCustomers;
                
                const pendingUsersEl = document.getElementById('pendingUsers');
                if (pendingUsersEl) pendingUsersEl.textContent = 0;
                
                console.log('[DASHBOARD] 사업자:', totalBusinessUsers, '고객:', totalCustomers);
                
                // 오더 통계
                const totalOrders = data.totalOrders || 0;
                const pendingOrders = data.pendingOrders || 0;
                const completedOrders = data.completedOrders || 0;
                
                const totalOrdersEl = document.getElementById('totalOrders');
                if (totalOrdersEl) totalOrdersEl.textContent = totalOrders;
                
                const pendingOrdersEl = document.getElementById('pendingOrders');
                if (pendingOrdersEl) pendingOrdersEl.textContent = pendingOrders;
                
                const completedOrdersEl = document.getElementById('completedOrders');
                if (completedOrdersEl) completedOrdersEl.textContent = completedOrders;
                
                console.log('[DASHBOARD] 오더 - 전체:', totalOrders, '입찰중:', pendingOrders, '완료:', completedOrders);
                
                // 견적 통계
                const totalEstimates = data.totalEstimates || 0;
                const pendingEstimates = data.pendingEstimates || 0;
                const completedEstimates = data.completedEstimates || 0;
                const inProgressEstimates = data.inProgressEstimates || 0;
                
                const totalEstimatesEl = document.getElementById('totalEstimates');
                if (totalEstimatesEl) totalEstimatesEl.textContent = totalEstimates;
                
                const pendingEstimatesEl = document.getElementById('pendingEstimates');
                if (pendingEstimatesEl) pendingEstimatesEl.textContent = pendingEstimates;
                
                const approvedEstimatesEl = document.getElementById('approvedEstimates');
                if (approvedEstimatesEl) approvedEstimatesEl.textContent = data.approvedEstimates || 0;
                
                const completedEstimatesEl = document.getElementById('completedEstimates');
                if (completedEstimatesEl) completedEstimatesEl.textContent = completedEstimates;
                
                const inProgressEstimatesEl = document.getElementById('inProgressEstimates');
                if (inProgressEstimatesEl) inProgressEstimatesEl.textContent = inProgressEstimates;
                
                const awardedEstimatesEl = document.getElementById('awardedEstimates');
                if (awardedEstimatesEl) awardedEstimatesEl.textContent = data.awardedEstimates || 0;
                
                const transferredEstimatesEl = document.getElementById('transferredEstimates');
                if (transferredEstimatesEl) transferredEstimatesEl.textContent = data.transferredEstimates || 0;
                
                console.log('[DASHBOARD] 견적 - 전체:', totalEstimates, '대기:', pendingEstimates, '완료:', completedEstimates, '진행중:', inProgressEstimates);
                
                // 금액 통계
                const totalOrderAmount = data.totalOrderAmount || 0;
                const totalEstimateAmount = data.totalEstimateAmount || 0;
                const totalRevenue = data.totalRevenue || 0;
                
                const totalOrderAmountEl = document.getElementById('totalOrderAmount');
                if (totalOrderAmountEl) totalOrderAmountEl.textContent = '₩' + totalOrderAmount.toLocaleString('ko-KR');
                
                const totalEstimateAmountEl = document.getElementById('totalEstimateAmount');
                if (totalEstimateAmountEl) totalEstimateAmountEl.textContent = '₩' + totalEstimateAmount.toLocaleString('ko-KR');
                
                const totalRevenueEl = document.getElementById('totalRevenue');
                if (totalRevenueEl) totalRevenueEl.textContent = '₩' + totalRevenue.toLocaleString('ko-KR');
                
                console.log('[DASHBOARD] 금액 - 오더:', totalOrderAmount, '견적:', totalEstimateAmount, '수익:', totalRevenue);
            } catch (error) {
                console.error('대시보드 로드 오류:', error);
                alert('대시보드 데이터를 불러오는데 실패했습니다: ' + error.message);
            }
        }

// 권한 조회 및 UI 제어
async function loadAdminMe() {
    try {
        const me = await apiCall('/me');
        ADMIN_ROLE = me.role || 'business';
        // 권한에 따라 UI 버튼 제어
        if (!(me.permissions?.canManageUsers)) {
            const userSection = document.querySelector('h2:nth-of-type(1)'); // 사용자 관리 섹션 헤더 탐색 (간단)
            // no-op for brevity
        }
        if (!(me.permissions?.canManageAds)) {
            const btnNewAd = document.getElementById('btnNewAd');
            if (btnNewAd) btnNewAd.style.display = 'none';
        }
    } catch (e) {
        console.warn('관리자 권한 조회 실패:', e);
    }
}

// 전체 사용자 목록 저장
let allUsers = [];

// 사용자 목록 로드
async function loadUsers() {
    try {
        console.log('[loadUsers] 사용자 목록 로딩 시작...');
        // 캐시 방지를 위해 타임스탬프 추가
        const timestamp = new Date().getTime();
        allUsers = await apiCall(`/users?t=${timestamp}`);
        console.log('[loadUsers] 받은 사용자 수:', allUsers.length);
        console.log('[loadUsers] 사용자 목록:', allUsers);
        
        if (!Array.isArray(allUsers)) {
            console.error('[loadUsers] 응답이 배열이 아닙니다:', allUsers);
            throw new Error('잘못된 응답 형식');
        }
        
        // 검색창 초기화
        const searchInput = document.getElementById('userSearchInput');
        if (searchInput) {
            searchInput.value = '';
        }
        
        displayUsers(allUsers);
    } catch (error) {
        console.error('[loadUsers] 에러:', error);
        document.getElementById('userTableContainer').innerHTML = 
            '<div class="error">사용자 목록을 불러오는데 실패했습니다: ' + error.message + '</div>';
    }
}

// 사용자 검색 필터링
function filterUsers(searchTerm) {
    if (!searchTerm || searchTerm.trim() === '') {
        displayUsers(allUsers);
        return;
    }
    
    const term = searchTerm.toLowerCase().trim();
    const filtered = allUsers.filter(user => {
        const businessName = (user.businessName || user.businessname || '').toLowerCase();
        const name = (user.name || '').toLowerCase();
        const phone = (user.phoneNumber || user.phonenumber || '').replace(/\D/g, '');
        const searchPhone = term.replace(/\D/g, '');
        
        return businessName.includes(term) || 
               name.includes(term) || 
               (searchPhone && phone.includes(searchPhone));
    });
    
    displayUsers(filtered);
}

        // 사용자 표시
        function displayUsers(users) {
            const container = document.getElementById('userTableContainer');
            
            if (users.length === 0) {
                container.innerHTML = `
                    <div class="empty-state">
                        <span class="material-icons">people_outline</span>
                        <p>등록된 사용자가 없습니다</p>
                    </div>
                `;
                return;
            }

            const table = `
                <div class="table-container">
                    <table class="table">
                        <thead>
                            <tr>
                                <th>상호</th>
                                <th>사장님 성함</th>
                                <th>카카오 ID</th>
                                <th>관리자</th>
                                <th>승인 상태</th>
                                <th>진위확인</th>
                                <th>가입일</th>
                                <th>작업</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${users.map(user => {
                                const isBusiness = user.role === 'business';
                                let verifyBadge = '<span style="color:#999;">-</span>';
                                if (isBusiness) {
                                    if (user.business_verify_bypass) {
                                        verifyBadge = '<span class="status-badge" style="background:#e0f2fe;color:#075985;">관리자 우회</span>';
                                    } else {
                                        const s = user.business_verify_status || 'unverified';
                                        const cfg = {
                                            verified: ['#15803d', '#e6f4ea', '인증 완료'],
                                            failed: ['#b91c1c', '#fee2e2', '실패'],
                                            closed: ['#b91c1c', '#fee2e2', '휴/폐업'],
                                            unverified: ['#92400e', '#fef3c7', '미인증'],
                                        }[s] || ['#92400e', '#fef3c7', '미인증'];
                                        verifyBadge = `<span class="status-badge" style="background:${cfg[1]};color:${cfg[0]};">${cfg[2]}</span>`;
                                    }
                                }
                                return `
                                <tr>
                                    <td><strong>${user.businessName || user.businessname || '-'}</strong></td>
                                    <td>
                                        <span class="clickable" data-user-id="${user.id}" style="color: #1a73e8; cursor: pointer; text-decoration: underline;">
                                            ${user.name || '성함 없음'}
                                        </span>
                                    </td>
                                    <td><code>${user.kakao_id || user.external_id || '-'}</code></td>
                                    <td>
                                        ${user.is_admin ? 
                                            '<span class="status-badge approved" style="background: #e6f4ea; color: #15803d;">관리자</span>' : 
                                            '<span style="color: #999;">-</span>'
                                        }
                                    </td>
                                    <td>
                                        <span class="status-badge ${(user.businessStatus || user.businessstatus || 'pending')}">
                                            ${getStatusText(user.businessStatus || user.businessstatus)}
                                        </span>
                                    </td>
                                    <td>${verifyBadge}</td>
                                    <td>${new Date(user.createdAt || user.createdat).toLocaleDateString('ko-KR')}</td>
                                    <td>
                                        <button class="btn btn-secondary btn-sm" data-user-id="${user.id}" data-action="view" style="margin-right: 0.5rem;">
                                            <span class="material-icons" style="font-size: 1rem;">visibility</span>
                                            상세 보기
                                        </button>
                                    </td>
                                </tr>`;
                            }).join('')}
                        </tbody>
                    </table>
                </div>
            `;
            
            container.innerHTML = table;
            
            // 사용자 이름 클릭 이벤트 리스너 설정
            const clickableCells = container.querySelectorAll('.clickable');
            clickableCells.forEach(cell => {
                cell.addEventListener('click', () => {
                    const userId = cell.getAttribute('data-user-id');
                    showUserDetail(userId);
                });
            });

            // 사용자 액션 버튼 이벤트 리스너 설정
            const actionButtons = container.querySelectorAll('[data-action]');
            actionButtons.forEach(button => {
                button.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const userId = button.getAttribute('data-user-id');
                    const action = button.getAttribute('data-action');
                    
                    switch(action) {
                        case 'view':
                            showUserDetail(userId);
                            break;
                        case 'approve':
                            approveUser(userId);
                            break;
                        case 'reject':
                            rejectUser(userId);
                            break;
                        case 'delete':
                            deleteUser(userId);
                            break;
                    }
                });
            });
        }

        // 견적 목록 로드
async function loadEstimates() {
    try {
        const params = buildEstimateQueryParams();
        const qs = params ? `?${params}` : '';
        allEstimates = await apiCall(`/estimates${qs}`);
        estimatesPage = 1; // Reset to first page
        displayEstimates();
    } catch (error) {
        document.getElementById('estimateTableContainer').innerHTML = 
            '<div class="error">견적 목록을 불러오는데 실패했습니다.</div>';
    }
}

        // 견적 표시 (페이지네이션 및 정렬 포함)
        function displayEstimates() {
            const container = document.getElementById('estimateTableContainer');
            
            if (allEstimates.length === 0) {
                container.innerHTML = '<div class="loading">등록된 견적이 없습니다.</div>';
                return;
            }

            // 정렬 적용
            let sortedEstimates = [...allEstimates];
            if (estimatesSortColumn) {
                sortedEstimates.sort((a, b) => {
                    let aVal = a[estimatesSortColumn];
                    let bVal = b[estimatesSortColumn];
                    
                    // 날짜 처리
                    if (estimatesSortColumn === 'createdAt' || estimatesSortColumn === 'createdat') {
                        aVal = new Date(a.createdAt || a.createdat || 0).getTime();
                        bVal = new Date(b.createdAt || b.createdat || 0).getTime();
                    }
                    
                    // 금액 처리
                    if (estimatesSortColumn === 'amount' || estimatesSortColumn === 'estimatedPrice') {
                        aVal = a.amount || a.estimatedPrice || 0;
                        bVal = b.amount || b.estimatedPrice || 0;
                    }
                    
                    // 문자열 비교
                    if (typeof aVal === 'string') {
                        aVal = (aVal || '').toLowerCase();
                        bVal = (bVal || '').toLowerCase();
                    }
                    
                    if (aVal < bVal) return estimatesSortDirection === 'asc' ? -1 : 1;
                    if (aVal > bVal) return estimatesSortDirection === 'asc' ? 1 : -1;
                    return 0;
                });
            }

            // 페이지네이션 적용
            const totalPages = Math.ceil(sortedEstimates.length / estimatesPerPage);
            const startIdx = (estimatesPage - 1) * estimatesPerPage;
            const endIdx = startIdx + estimatesPerPage;
            const paginatedEstimates = sortedEstimates.slice(startIdx, endIdx);

            const table = `
                <div class="table-container">
                    <table class="table">
                        <thead>
                            <tr>
                                <th class="sortable" data-column="title">제목</th>
                                <th class="sortable" data-column="customerName">고객</th>
                                <th class="sortable" data-column="businessName">사업자</th>
                                <th class="sortable" data-column="amount">금액</th>
                                <th class="sortable" data-column="status">상태</th>
                                <th class="sortable" data-column="createdAt">생성일</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${paginatedEstimates.map(e => {
                                const title = e.title || e.description || '제목 없음';
                                const customerName = e.customerName || e.customername || '고객명 없음';
                                const businessName = e.businessName || e.businessname || '상호명 없음';
                                const amountRaw = (e.amount !== undefined && e.amount !== null) ? e.amount : (e.estimatedPrice !== undefined ? e.estimatedPrice : null);
                                const amountText = (typeof amountRaw === 'number') ? amountRaw.toLocaleString() + '원' : '금액 없음';
                                const createdAt = e.createdAt || e.createdat;
                                const createdAtText = createdAt ? new Date(createdAt).toLocaleDateString() : '-';
                                const status = e.status || '-';
                                return `
                                <tr>
                                    <td class="clickable-title" data-estimate-id="${e.id}" style="cursor: pointer; color: #1a73e8; text-decoration: underline;" onclick="showEstimateDetail('${e.id}')">${title}</td>
                                    <td>${customerName}</td>
                                    <td>${businessName}</td>
                                    <td>${amountText}</td>
                                    <td>
                                        <span class="status-badge status-${status}">${getStatusText(status)}</span>
                                    </td>
                                    <td>${createdAtText}</td>
                                </tr>`;
                            }).join('')}
                        </tbody>
                    </table>
                </div>
                <div class="pagination">
                    <button onclick="changeEstimatePage(-1)" ${estimatesPage === 1 ? 'disabled' : ''}>이전</button>
                    <span>페이지 ${estimatesPage} / ${totalPages} (전체 ${sortedEstimates.length}건)</span>
                    <button onclick="changeEstimatePage(1)" ${estimatesPage >= totalPages ? 'disabled' : ''}>다음</button>
                </div>
            `;
            
            container.innerHTML = table;
            
            // 정렬 표시 업데이트
            if (estimatesSortColumn) {
                const headers = container.querySelectorAll('th');
                headers.forEach(th => {
                    const col = th.getAttribute('data-column');
                    if (col === estimatesSortColumn) {
                        th.classList.add(estimatesSortDirection === 'asc' ? 'sort-asc' : 'sort-desc');
                    }
                });
            }
            
            // 컬럼 헤더 클릭 이벤트 리스너
            const headers = container.querySelectorAll('th.sortable');
            headers.forEach(th => {
                th.addEventListener('click', () => {
                    const column = th.getAttribute('data-column');
                    if (estimatesSortColumn === column) {
                        estimatesSortDirection = estimatesSortDirection === 'asc' ? 'desc' : 'asc';
                    } else {
                        estimatesSortColumn = column;
                        estimatesSortDirection = 'asc';
                    }
                    displayEstimates();
                });
            });
            
            // 견적 제목 클릭 이벤트 리스너 설정
            const clickableTitles = container.querySelectorAll('.clickable-title');
            clickableTitles.forEach(title => {
                title.addEventListener('click', () => {
                    const estimateId = title.getAttribute('data-estimate-id');
                    showEstimateDetail(estimateId);
                });
            });
        }

        // 페이지 변경
        function changeEstimatePage(delta) {
            const totalPages = Math.ceil(allEstimates.length / estimatesPerPage);
            estimatesPage = Math.max(1, Math.min(estimatesPage + delta, totalPages));
            displayEstimates();
        }

// 상태 텍스트 변환
function getStatusText(status) {
    const statusMap = {
        'pending': '대기중',
        'approved': '승인됨',
        'rejected': '거절됨',
        'completed': '완료',
        'in_progress': '진행중',
        'awarded': '입찰 완료',
        'transferred': '이전됨'
    };
    return statusMap[status] || status;
}

        // 사용자 승인
        async function approveUser(userId) {
            try {
                console.log('사용자 승인 시도:', userId);
                const response = await apiCall(`/users/${userId}/status`, {
                    method: 'PATCH',
                    body: JSON.stringify({ status: 'approved' })
                });
                console.log('승인 응답:', response);
                
                // 서버 응답이 성공하면 즉시 UI 업데이트
                if (response.success) {
                    alert('사용자가 승인되었습니다.');
                    // Promise.all로 병렬 실행
                    await Promise.all([loadUsers(), loadDashboard()]);
                } else {
                    throw new Error('승인 실패');
                }
            } catch (error) {
                console.error('승인 오류:', error);
                alert('사용자 승인에 실패했습니다: ' + error.message);
            }
        }

        // 사용자 거절
        async function rejectUser(userId) {
            try {
                console.log('사용자 거절 시도:', userId);
                const response = await apiCall(`/users/${userId}/status`, {
                    method: 'PATCH',
                    body: JSON.stringify({ status: 'rejected' })
                });
                console.log('거절 응답:', response);
                
                // 서버 응답이 성공하면 즉시 UI 업데이트
                if (response.success) {
                    alert('사용자가 거절되었습니다.');
                    // Promise.all로 병렬 실행
                    await Promise.all([loadUsers(), loadDashboard()]);
                } else {
                    throw new Error('거절 실패');
                }
            } catch (error) {
                console.error('거절 오류:', error);
                alert('사용자 거절에 실패했습니다: ' + error.message);
            }
        }

// 사용자 삭제
async function deleteUser(userId) {
    if (!confirm('정말로 이 사용자를 삭제하시겠습니까?\n\n⚠️ 관련된 모든 데이터도 함께 삭제됩니다:\n- 견적 및 입찰\n- 오더 및 작업\n- 채팅 메시지\n- 알림\n- 커뮤니티 게시글/댓글')) {
        return;
    }

    try {
        // 모든 사용자에 대해 CASCADE 삭제 사용
        const response = await apiCall(`/users/${userId}`, {
            method: 'DELETE'
        });
        
        // 삭제된 데이터 통계 표시
        if (response.deleted_counts) {
            const counts = response.deleted_counts;
            let message = '사용자가 삭제되었습니다.\n\n삭제된 데이터:\n';
            if (counts.estimates > 0) message += `- 견적: ${counts.estimates}개\n`;
            if (counts.bids > 0) message += `- 입찰: ${counts.bids}개\n`;
            if (counts.listings > 0) message += `- 오더: ${counts.listings}개\n`;
            if (counts.jobs > 0) message += `- 작업: ${counts.jobs}개\n`;
            if (counts.chats > 0) message += `- 채팅방: ${counts.chats}개\n`;
            if (counts.notifications > 0) message += `- 알림: ${counts.notifications}개\n`;
            alert(message);
        } else {
            alert('사용자가 삭제되었습니다.');
        }
        
        loadUsers();
        loadDashboard();
    } catch (error) {
        console.error('사용자 삭제 오류:', error);
        alert('사용자 삭제에 실패했습니다: ' + error.message);
    }
}

// 관리자 권한 토글
async function toggleAdmin(userId) {
    try {
        const user = allUsers.find(u => u.id === userId);
        if (!user) {
            alert('사용자를 찾을 수 없습니다.');
            return;
        }
        
        const newAdminStatus = !user.is_admin;
        const confirmMsg = newAdminStatus 
            ? '이 사용자를 관리자로 지정하시겠습니까?' 
            : '이 사용자의 관리자 권한을 해제하시겠습니까?';
        
        if (!confirm(confirmMsg)) {
            return;
        }
        
        const response = await apiCall(`/users/${userId}/admin`, {
            method: 'PATCH',
            body: JSON.stringify({ is_admin: newAdminStatus })
        });
        
        if (response.success) {
            alert(response.message);
            loadUsers();
        }
    } catch (error) {
        alert('관리자 권한 변경에 실패했습니다: ' + error.message);
    }
}

// 사업자 진위확인 우회(화이트리스트) 토글
async function toggleVerifyBypass(userId) {
    try {
        const user = allUsers.find(u => u.id === userId);
        if (!user) {
            alert('사용자를 찾을 수 없습니다.');
            return;
        }

        const current = user.business_verify_bypass === true;
        const next = !current;

        let reason = null;
        if (next) {
            reason = prompt('인증 우회 사유를 입력하세요 (예: 임시 협력업체, 내부 테스트). 취소하면 진행하지 않습니다.', '');
            if (reason === null) return;
            if (!reason || !reason.trim()) {
                alert('사유를 반드시 입력해 주세요.');
                return;
            }
        } else {
            const ok = confirm('이 사업자의 인증 우회를 해제하시겠습니까?\n해제 후에는 사업자번호 등록·진위확인이 완료되어야 오더 등록·입찰·낙찰이 가능합니다.');
            if (!ok) return;
        }

        const response = await apiCall(`/users/${userId}/verify-bypass`, {
            method: 'PATCH',
            body: JSON.stringify({ bypass: next, reason: reason || undefined }),
        });

        if (response && response.success) {
            alert(response.message || '변경되었습니다.');
            await Promise.all([loadUsers(), loadDashboard?.()]);
            if (typeof showUserDetail === 'function') showUserDetail(userId);
        } else {
            throw new Error(response?.message || '응답 형식 오류');
        }
    } catch (error) {
        alert('인증 우회 변경에 실패했습니다: ' + (error?.message || error));
    }
}

async function toggleVerifyBypassFromModal() {
    if (!currentUserId) return;
    await toggleVerifyBypass(currentUserId);
}

        // 검색 기능 및 이벤트 리스너 설정
        document.addEventListener('DOMContentLoaded', () => {
            // 로그인 체크
            if (!checkLogin()) {
                return;
            }
            
            // 검색 기능 이벤트 리스너
            document.getElementById('userSearch')?.addEventListener('input', debounce(async (e) => {
                const query = e.target.value;
                if (query.length > 0) {
                    try {
                        const users = await apiCall(`/users/search?q=${encodeURIComponent(query)}`);
                        displayUsers(users);
                    } catch (error) {
                        console.error('사용자 검색 오류:', error);
                    }
                } else {
                    loadUsers();
                }
            }, 300));

            document.getElementById('estimateSearch').addEventListener('input', debounce(async (e) => {
                const query = e.target.value;
                if (query.length > 0) {
                    try {
                        const base = `/estimates/search?q=${encodeURIComponent(query)}`;
                        const params = buildEstimateQueryParams({ includeText:false });
                        const qs = params ? `&${params}` : '';
                        const estimates = await apiCall(`${base}${qs}`);
                        displayEstimates(estimates);
                    } catch (error) {
                        console.error('견적 검색 오류:', error);
                    }
                } else {
                        loadEstimates();
                }
            }, 300));

            // 필터 버튼
            document.getElementById('applyEstimateFilters').addEventListener('click', loadEstimates);
            document.getElementById('resetEstimateFilters').addEventListener('click', () => {
                document.getElementById('statusFilter').value = 'all';
                document.getElementById('startDateFilter').value = '';
                document.getElementById('endDateFilter').value = '';
                document.getElementById('phoneFilter').value = '';
                document.getElementById('estimateSearch').value = '';
                loadEstimates();
            });

            // 모달 닫기 버튼 이벤트 리스너
            document.getElementById('closeEstimateModal').addEventListener('click', closeEstimateModal);
            document.getElementById('closeEstimateModalBtn').addEventListener('click', closeEstimateModal);
            document.getElementById('closeUserModal').addEventListener('click', closeUserModal);
            document.getElementById('closeUserModalBtn').addEventListener('click', closeUserModal);
            document.getElementById('closeStatsModalBtn').addEventListener('click', closeStatsModal);

            // 견적 모달 버튼 이벤트 리스너
            document.getElementById('updateEstimateStatus').addEventListener('click', updateEstimateStatus);

            // 사용자 모달 버튼 이벤트 리스너
            document.getElementById('approveUserFromModal').addEventListener('click', approveUserFromModal);
            document.getElementById('rejectUserFromModal').addEventListener('click', rejectUserFromModal);

            // 통계 숫자 클릭 이벤트 리스너
            setupStatsClickListeners();

            // 페이지 로드 시 데이터 로드
            console.log('[PAGE LOAD] DOM이 로드되었습니다. 데이터를 불러오기 시작합니다.');
            loadDashboard();
            loadUsers();
            loadEstimates();
            // Call 현황 초기 로드 및 필터 바인딩
            const applyCallFiltersBtn = document.getElementById('applyCallFilters');
            if (applyCallFiltersBtn) {
                applyCallFiltersBtn.addEventListener('click', loadCalls);
            }
            if (typeof loadCalls === 'function') {
                loadCalls();
            }
            // 광고 로드 및 버튼 바인딩
            if (typeof loadAds === 'function') {
                loadAds();
            }
            const reloadAdsBtn = document.getElementById('btnReloadAds');
            if (reloadAdsBtn) reloadAdsBtn.addEventListener('click', loadAds);
            const newAdBtn = document.getElementById('btnNewAd');
            if (newAdBtn) newAdBtn.addEventListener('click', showAdModal);

            // 공지 배너
            const newAnnBtn = document.getElementById('btnNewAnnouncement');
            if (newAnnBtn) newAnnBtn.addEventListener('click', showAnnouncementModal);
            // 공지 미리보기 실시간 업데이트
            ['announcementMessage', 'announcementBgColor', 'announcementTextColor'].forEach(id => {
                const el = document.getElementById(id);
                if (el) el.addEventListener('input', updateAnnouncementPreview);
            });
            const statsAdBtn = document.getElementById('btnAdsStats');
            if (statsAdBtn) statsAdBtn.addEventListener('click', showAdsStats);
        });

        // 쿼리 파라미터 구성
        function buildEstimateQueryParams(opts = { includeText:true }) {
            const status = (document.getElementById('statusFilter')?.value || '').trim();
            const startDate = (document.getElementById('startDateFilter')?.value || '').trim();
            const endDate = (document.getElementById('endDateFilter')?.value || '').trim();
            const phone = (document.getElementById('phoneFilter')?.value || '').trim();
            const text = (document.getElementById('estimateSearch')?.value || '').trim();
            const parts = [];
            if (status && status !== 'all') parts.push(`status=${encodeURIComponent(status)}`);
            if (startDate) parts.push(`startDate=${encodeURIComponent(startDate)}`);
            if (endDate) parts.push(`endDate=${encodeURIComponent(endDate)}`);
            if (phone) parts.push(`phone=${encodeURIComponent(phone)}`);
            if (opts.includeText && text) parts.push(`q=${encodeURIComponent(text)}`);
            return parts.join('&');
        }

        // 디바운스 함수
        function debounce(func, wait) {
            let timeout;
            return function executedFunction(...args) {
                const later = () => {
                    clearTimeout(timeout);
                    func(...args);
                };
                clearTimeout(timeout);
                timeout = setTimeout(later, wait);
            };
        }

        // 전역 변수로 현재 선택된 견적/사용자 ID 저장
        let currentEstimateId = null;
        let currentUserId = null;

        // 견적 상세 보기 모달 표시
        async function showEstimateDetail(estimateId) {
            try {
                console.log('견적 상세 보기 시도:', estimateId);
                currentEstimateId = estimateId;
                const estimates = await apiCall('/estimates');
                console.log('견적 목록:', estimates);
                const estimate = estimates.find(e => e.id === estimateId);
                console.log('찾은 견적:', estimate);
                
                if (!estimate) {
                    alert('견적을 찾을 수 없습니다.');
                    return;
                }

                document.getElementById('estimateModalTitle').textContent = `견적 상세 정보 - ${estimate.title}`;
                
                const modalBody = document.getElementById('estimateModalBody');
                modalBody.innerHTML = `
                    <div class="detail-row">
                        <div class="detail-label">제목:</div>
                        <div class="detail-value">${estimate.title || '제목 없음'}</div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">고객명:</div>
                        <div class="detail-value">${estimate.customerName || '고객명 없음'}</div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">고객 연락처:</div>
                        <div class="detail-value">${estimate.customerPhone || '연락처 없음'}</div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">주소:</div>
                        <div class="detail-value">${estimate.address || '주소 없음'}</div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">설명:</div>
                        <div class="detail-value">${estimate.description || '설명 없음'}</div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">카테고리:</div>
                        <div class="detail-value">${estimate.category || '카테고리 없음'}</div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">방문 예정일:</div>
                        <div class="detail-value">${estimate.visitDate ? new Date(estimate.visitDate).toLocaleDateString() : '날짜 없음'}</div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">현재 상태:</div>
                        <div class="detail-value">
                            <span class="status-badge status-${estimate.status}">
                                ${getStatusText(estimate.status)}
                            </span>
                        </div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">상태 변경:</div>
                        <div class="detail-value">
                            <select id="statusSelector" class="status-selector">
                                <option value="pending" ${estimate.status === 'pending' ? 'selected' : ''}>대기중</option>
                                <option value="approved" ${estimate.status === 'approved' ? 'selected' : ''}>승인됨</option>
                                <option value="rejected" ${estimate.status === 'rejected' ? 'selected' : ''}>거절됨</option>
                                <option value="completed" ${estimate.status === 'completed' ? 'selected' : ''}>완료</option>
                                <option value="in_progress" ${estimate.status === 'in_progress' ? 'selected' : ''}>진행중</option>
                                <option value="awarded" ${estimate.status === 'awarded' ? 'selected' : ''}>입찰 완료</option>
                                <option value="transferred" ${estimate.status === 'transferred' ? 'selected' : ''}>이전됨</option>
                            </select>
                        </div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">생성일:</div>
                        <div class="detail-value">${new Date(estimate.createdAt).toLocaleString()}</div>
                    </div>
                    <div class="detail-row">
                        <div class="detail-label">수정일:</div>
                        <div class="detail-value">${new Date(estimate.updatedAt).toLocaleString()}</div>
                    </div>
                `;

                document.getElementById('estimateModal').style.display = 'block';
            } catch (error) {
                console.error('견적 상세 정보 로드 오류:', error);
                alert('견적 상세 정보를 불러오는데 실패했습니다: ' + error.message);
            }
        }

        // 견적 상태 업데이트
        async function updateEstimateStatus() {
            if (!currentEstimateId) return;
            
            const statusSelector = document.getElementById('statusSelector');
            const newStatus = statusSelector.value;
            
            try {
                console.log('견적 상태 업데이트 시도:', currentEstimateId, '->', newStatus);
                const response = await apiCall(`/estimates/${currentEstimateId}/status`, {
                    method: 'PATCH',
                    body: JSON.stringify({ status: newStatus })
                });
                console.log('상태 업데이트 응답:', response);
                
                alert('견적 상태가 업데이트되었습니다.');
                closeEstimateModal();
                loadEstimates();
                loadDashboard();
            } catch (error) {
                console.error('상태 업데이트 오류:', error);
                alert('견적 상태 업데이트에 실패했습니다: ' + error.message);
            }
        }

        // 견적 모달 닫기
        function closeEstimateModal() {
            document.getElementById('estimateModal').style.display = 'none';
            currentEstimateId = null;
        }

        // 사용자 상세 보기 모달 표시
        async function showUserDetail(userId) {
            try {
                currentUserId = userId;
                const users = await apiCall('/users');
                const user = users.find(u => u.id === userId);
                
                if (!user) {
                    alert('사용자를 찾을 수 없습니다.');
                    return;
                }

                document.getElementById('userModalTitle').textContent = `사용자 상세 정보 - ${user.name || '성함 없음'}`;
                
                const modalBody = document.getElementById('userModalBody');
                const userStatus = user.businessStatus || user.businessstatus || 'pending';
                modalBody.innerHTML = `
                    <div style="margin-bottom: 1rem;">
                        <strong>사장님 성함:</strong> ${user.name || '성함 없음'}
                    </div>
                    <div style="margin-bottom: 1rem;">
                        <strong>이메일:</strong> ${user.email || '이메일 없음'}
                    </div>
                    <div style="margin-bottom: 1rem;">
                        <strong>역할:</strong> ${user.role === 'business' ? '사업자' : '고객'}
                    </div>
                    <div style="margin-bottom: 1rem;">
                        <strong>연락처:</strong> ${user.phoneNumber || user.phonenumber || '연락처 없음'}
                    </div>
                    ${user.role === 'business' ? `
                        <div style="margin-bottom: 1rem;">
                            <strong>상호명:</strong> ${user.businessName || user.businessname || '상호명 없음'}
                        </div>
                        <div style="margin-bottom: 1rem;">
                            <strong>사업자등록번호:</strong> ${user.businessNumber || user.businessnumber || '등록번호 없음'}
                        </div>
                        <div style="margin-bottom: 1rem;">
                            <strong>주소:</strong> ${user.address || '주소 없음'}
                        </div>
                        <div style="margin-bottom: 1rem;">
                            <strong>서비스 지역:</strong> ${user.serviceAreas || user.serviceareas ? (user.serviceAreas || user.serviceareas).join(', ') : '지역 없음'}
                        </div>
                        <div style="margin-bottom: 1rem;">
                            <strong>전문 분야:</strong> ${user.specialties ? user.specialties.join(', ') : '전문 분야 없음'}
                        </div>
                    ` : ''}
                    <div style="margin-bottom: 1rem;">
                        <strong>현재 상태:</strong> 
                        <span class="status-badge status-${userStatus}">
                            ${getStatusText(userStatus)}
                        </span>
                    </div>
                    <div style="margin-bottom: 1rem;">
                        <strong>가입일:</strong> ${new Date(user.createdAt || user.createdat).toLocaleString()}
                    </div>
                    <div style="margin-bottom: 1rem;">
                        <strong>수정일:</strong> ${new Date(user.updatedAt || user.updatedat).toLocaleString()}
                    </div>
                    <div style="margin-bottom: 1rem;">
                        <strong>관리자 권한:</strong> 
                        <span class="status-badge ${user.is_admin ? 'approved' : 'pending'}">
                            ${user.is_admin ? '관리자' : '일반 사용자'}
                        </span>
                    </div>
                    ${user.role === 'business' ? `
                        <div style="margin-bottom: 1rem; padding: 12px; border: 1px solid #e0e0e0; border-radius: 8px; background:#fafafa;">
                            <div style="font-weight:600; margin-bottom: 8px;">사업자등록 진위확인</div>
                            <div style="margin-bottom: 4px;">
                                <strong>상태:</strong>
                                ${(() => {
                                    if (user.business_verify_bypass) return '<span class="status-badge approved" style="background:#e0f2fe;color:#075985;">관리자 우회</span>';
                                    const s = user.business_verify_status || 'unverified';
                                    const map = { verified: ['approved','인증 완료','#15803d','#e6f4ea'], failed: ['rejected','실패','#b91c1c','#fee2e2'], closed: ['rejected','휴/폐업','#b91c1c','#fee2e2'], unverified: ['pending','미인증','#92400e','#fef3c7'] };
                                    const [_, label, color, bg] = map[s] || map.unverified;
                                    return `<span class="status-badge" style="background:${bg};color:${color};">${label}</span>`;
                                })()}
                            </div>
                            <div style="margin-bottom: 4px;">
                                <strong>인증일:</strong> ${user.business_verified_at ? new Date(user.business_verified_at).toLocaleString('ko-KR') : '-'}
                            </div>
                            <div style="margin-bottom: 4px;">
                                <strong>유예 만료:</strong> ${user.business_grace_until ? new Date(user.business_grace_until).toLocaleString('ko-KR') : '-'}
                            </div>
                            ${user.business_verify_bypass ? `
                                <div style="margin-bottom: 4px;">
                                    <strong>우회 사유:</strong> ${user.business_verify_bypass_reason || '-'}
                                </div>
                                <div style="margin-bottom: 4px;">
                                    <strong>우회 지정 시각:</strong> ${user.business_verify_bypass_set_at ? new Date(user.business_verify_bypass_set_at).toLocaleString('ko-KR') : '-'}
                                </div>
                            ` : ''}
                        </div>
                    ` : ''}
                `;
                
                // 모달 footer 버튼 조건부 표시
                const modalFooter = document.querySelector('#userModal .modal-footer');
                const verifyBypassBtn = user.role === 'business' ? `
                    <button class="btn ${user.business_verify_bypass ? 'btn-warning' : 'btn-secondary'} btn-sm" onclick="toggleVerifyBypassFromModal()">
                        <span class="material-icons" style="font-size:1rem;">${user.business_verify_bypass ? 'lock_open' : 'verified_user'}</span>
                        ${user.business_verify_bypass ? '인증 우회 해제' : '인증 우회 지정'}
                    </button>
                ` : '';
                if (userStatus === 'approved') {
                    modalFooter.innerHTML = `
                        <button class="btn btn-secondary" onclick="closeUserModal()">닫기</button>
                        <button class="btn ${user.is_admin ? 'btn-warning' : 'btn-primary'} btn-sm" onclick="toggleAdminFromModal()" style="margin-right: auto;">
                            <span class="material-icons" style="font-size: 1rem;">${user.is_admin ? 'remove_moderator' : 'admin_panel_settings'}</span>
                            ${user.is_admin ? '관리자 해제' : '관리자 지정'}
                        </button>
                        ${verifyBypassBtn}
                        <button class="btn btn-info btn-sm" onclick="showEditUserForm()">
                            <span class="material-icons" style="font-size:1rem;">edit</span> 정보 수정
                        </button>
                        <button class="btn btn-danger btn-sm" onclick="deleteUserFromModal()">삭제</button>
                    `;
                } else {
                    modalFooter.innerHTML = `
                        <button class="btn btn-secondary" onclick="closeUserModal()">닫기</button>
                        <button class="btn btn-info btn-sm" onclick="showEditUserForm()">
                            <span class="material-icons" style="font-size:1rem;">edit</span> 정보 수정
                        </button>
                        <button class="btn btn-danger btn-sm" onclick="rejectUserFromModal()">거절</button>
                        <button class="btn btn-success btn-sm" onclick="approveUserFromModal()">승인</button>
                    `;
                }

                document.getElementById('userModal').style.display = 'block';
            } catch (error) {
                console.error('사용자 상세 정보 로드 오류:', error);
                alert('사용자 상세 정보를 불러오는데 실패했습니다.');
            }
        }

        // 사업자 정보 수정 폼 표시 (모달 내 인라인)
        function showEditUserForm() {
            if (!currentUserId) return;
            const user = allUsers.find(u => u.id === currentUserId);
            if (!user) return;

            const modalBody = document.getElementById('userModalBody');
            modalBody.innerHTML = `
                <div style="display:grid; gap:0.75rem;">
                    <div>
                        <label style="font-size:0.8rem; color:#666; font-weight:600;">상호명</label>
                        <input id="editBusinessname" type="text" value="${(user.businessname || user.businessName || '').replace(/"/g,'&quot;')}"
                            style="width:100%; padding:0.5rem 0.75rem; border:1px solid #ddd; border-radius:8px; margin-top:0.25rem;" />
                    </div>
                    <div>
                        <label style="font-size:0.8rem; color:#666; font-weight:600;">사장님 성함</label>
                        <input id="editName" type="text" value="${(user.name || '').replace(/"/g,'&quot;')}"
                            style="width:100%; padding:0.5rem 0.75rem; border:1px solid #ddd; border-radius:8px; margin-top:0.25rem;" />
                    </div>
                    <div>
                        <label style="font-size:0.8rem; color:#666; font-weight:600;">전화번호</label>
                        <input id="editPhone" type="tel" value="${(user.phonenumber || user.phoneNumber || '').replace(/"/g,'&quot;')}"
                            style="width:100%; padding:0.5rem 0.75rem; border:1px solid #ddd; border-radius:8px; margin-top:0.25rem;" />
                    </div>
                    <div>
                        <label style="font-size:0.8rem; color:#666; font-weight:600;">지역</label>
                        <input id="editRegion" type="text" value="${(user.region || '').replace(/"/g,'&quot;')}"
                            style="width:100%; padding:0.5rem 0.75rem; border:1px solid #ddd; border-radius:8px; margin-top:0.25rem;" />
                    </div>
                    <div>
                        <label style="font-size:0.8rem; color:#666; font-weight:600;">카테고리 / 전문분야</label>
                        <input id="editCategory" type="text" value="${(user.category || '').replace(/"/g,'&quot;')}"
                            style="width:100%; padding:0.5rem 0.75rem; border:1px solid #ddd; border-radius:8px; margin-top:0.25rem;" />
                    </div>
                    <div>
                        <label style="font-size:0.8rem; color:#666; font-weight:600;">사업자등록번호</label>
                        <input id="editBusinessnumber" type="text" value="${(user.businessnumber || user.businessNumber || '').replace(/"/g,'&quot;')}"
                            style="width:100%; padding:0.5rem 0.75rem; border:1px solid #ddd; border-radius:8px; margin-top:0.25rem;" />
                    </div>
                    <div>
                        <label style="font-size:0.8rem; color:#666; font-weight:600;">소개</label>
                        <textarea id="editDescription" rows="3"
                            style="width:100%; padding:0.5rem 0.75rem; border:1px solid #ddd; border-radius:8px; margin-top:0.25rem; resize:vertical;">${(user.description || '').replace(/</g,'&lt;')}</textarea>
                    </div>
                    <div>
                        <label style="font-size:0.8rem; color:#666; font-weight:600;">승인 상태</label>
                        <select id="editStatus"
                            style="width:100%; padding:0.5rem 0.75rem; border:1px solid #ddd; border-radius:8px; margin-top:0.25rem;">
                            <option value="pending" ${(user.businessstatus||user.businessStatus)==='pending'?'selected':''}>대기중</option>
                            <option value="approved" ${(user.businessstatus||user.businessStatus)==='approved'?'selected':''}>승인됨</option>
                            <option value="rejected" ${(user.businessstatus||user.businessStatus)==='rejected'?'selected':''}>거절됨</option>
                        </select>
                    </div>
                </div>
            `;
            document.getElementById('userModalTitle').textContent = '사업자 정보 수정';
            const modalFooter = document.querySelector('#userModal .modal-footer');
            modalFooter.innerHTML = `
                <button class="btn btn-secondary" onclick="showUserDetail('${currentUserId}')">← 취소</button>
                <button class="btn btn-primary" onclick="saveUserEdit()">
                    <span class="material-icons" style="font-size:1rem;">save</span> 저장
                </button>
            `;
        }

        // 사업자 정보 수정 저장
        async function saveUserEdit() {
            if (!currentUserId) return;
            const payload = {
                businessname: document.getElementById('editBusinessname')?.value.trim() || undefined,
                name: document.getElementById('editName')?.value.trim() || undefined,
                phonenumber: document.getElementById('editPhone')?.value.trim() || undefined,
                region: document.getElementById('editRegion')?.value.trim() || undefined,
                category: document.getElementById('editCategory')?.value.trim() || undefined,
                businessnumber: document.getElementById('editBusinessnumber')?.value.trim() || undefined,
                description: document.getElementById('editDescription')?.value.trim() || undefined,
                businessstatus: document.getElementById('editStatus')?.value || undefined,
            };
            // 빈 문자열 제거
            Object.keys(payload).forEach(k => { if (!payload[k]) delete payload[k]; });

            try {
                const res = await apiCall(`/users/${currentUserId}`, {
                    method: 'PATCH',
                    body: JSON.stringify(payload),
                });
                if (res.success) {
                    alert('✅ 정보가 수정되었습니다.');
                    await loadUsers();
                    showUserDetail(currentUserId);
                } else {
                    alert('❌ 수정 실패: ' + (res.message || '알 수 없는 오류'));
                }
            } catch (e) {
                alert('❌ 수정 중 오류: ' + e.message);
            }
        }

        // 사용자 모달에서 승인
        async function approveUserFromModal() {
            if (!currentUserId) return;
            await approveUser(currentUserId);
            closeUserModal();
        }

        // 사용자 모달에서 거절
        async function rejectUserFromModal() {
            if (!currentUserId) return;
            await rejectUser(currentUserId);
            closeUserModal();
        }

        // 사용자 모달에서 삭제
        async function deleteUserFromModal() {
            if (!currentUserId) return;
            await deleteUser(currentUserId);
            closeUserModal();
        }

        // 사용자 모달에서 관리자 권한 토글
        async function toggleAdminFromModal() {
            if (!currentUserId) return;
            await toggleAdmin(currentUserId);
            // 모달 다시 열어서 업데이트된 정보 보여주기
            setTimeout(() => showUserDetail(currentUserId), 100);
        }

        // 사용자 모달 닫기
        function closeUserModal() {
            document.getElementById('userModal').style.display = 'none';
            currentUserId = null;
        }

        // 모달 외부 클릭 시 닫기
        window.onclick = function(event) {
            const modals = [
                { id: 'estimateModal', fn: closeEstimateModal },
                { id: 'userModal', fn: closeUserModal },
                { id: 'statsModal', fn: closeStatsModal },
                { id: 'adModal', fn: closeAdModal },
                { id: 'callModal', fn: closeCallModal },
                { id: 'postModal', fn: closePostModal },
                { id: 'chatModal', fn: closeChatModal },
                { id: 'announcementModal', fn: closeAnnouncementModal },
            ];
            modals.forEach(({ id, fn }) => {
                const el = document.getElementById(id);
                if (event.target === el) fn();
            });
        }

        // 사용자 타입별 상세 정보 표시
        async function showUsersByType(type) {
            try {
                const users = await apiCall('/users');
                let filteredUsers = [];
                let title = '';

                switch(type) {
                    case 'all':
                        filteredUsers = users;
                        title = '전체 사용자 목록';
                        break;
                    case 'business':
                        filteredUsers = users.filter(u => u.role === 'business');
                        title = '사업자 사용자 목록';
                        break;
                    case 'customer':
                        filteredUsers = users.filter(u => u.role === 'customer');
                        title = '고객 사용자 목록';
                        break;
                    case 'pending':
                        filteredUsers = users.filter(u => u.role === 'business' && (u.businessStatus || u.businessstatus) === 'pending');
                        title = '승인 대기 사업자 목록';
                        break;
                }

                document.getElementById('statsModalTitle').textContent = title;
                const modalBody = document.getElementById('statsModalBody');
                
                if (filteredUsers.length === 0) {
                    modalBody.innerHTML = '<div class="loading">해당 조건의 사용자가 없습니다.</div>';
                } else {
                    const table = `
                        <table class="table">
                            <thead>
                                <tr>
                                    <th>사장님 성함</th>
                                    <th>이메일</th>
                                    <th>역할</th>
                                    <th>상태</th>
                                    <th>가입일</th>
                                    <th>작업</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${filteredUsers.map(user => `
                                    <tr>
                                        <td class="clickable-cell" onclick="showUserDetail('${user.id}')" style="cursor: pointer; color: #1a73e8; text-decoration: underline;">${user.name || '성함 없음'}</td>
                                        <td>${user.email}</td>
                                        <td>${user.role === 'business' ? '사업자' : '고객'}</td>
                                        <td>
                                            <span class="status-badge status-${user.businessStatus || user.businessstatus || 'pending'}">
                                                ${getStatusText(user.businessStatus || user.businessstatus)}
                                            </span>
                                        </td>
                                        <td>${new Date(user.createdAt || user.createdat).toLocaleDateString()}</td>
                                        <td>
                                            ${user.role === 'business' && (user.businessStatus || user.businessstatus) === 'pending' ? `
                                                <button class="btn btn-success" onclick="approveUser('${user.id}')">승인</button>
                                                <button class="btn btn-danger" onclick="rejectUser('${user.id}')">거절</button>
                                            ` : ''}
                                            <button class="btn btn-danger" onclick="deleteUser('${user.id}')">삭제</button>
                                        </td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    `;
                    modalBody.innerHTML = table;
                }

                document.getElementById('statsModal').style.display = 'block';
            } catch (error) {
                console.error('사용자 상세 정보 로드 오류:', error);
                alert('사용자 상세 정보를 불러오는데 실패했습니다.');
            }
        }

        // 견적 상태별 상세 정보 표시
        async function showEstimatesByStatus(status) {
            try {
                const endpoint = status === 'all' ? '/estimates' : `/estimates?status=${encodeURIComponent(status)}`;
                const estimates = await apiCall(endpoint);
                const filteredEstimates = estimates;
                const titleMap = {
                    all: '전체 견적 목록',
                    pending: '대기중인 견적 목록',
                    approved: '승인된 견적 목록',
                    completed: '완료된 견적 목록',
                    in_progress: '진행중인 견적 목록',
                    awarded: '입찰 완료된 견적 목록',
                    transferred: '이전된 견적 목록',
                };
                const title = titleMap[status] || '견적 목록';

                document.getElementById('statsModalTitle').textContent = title;
                const modalBody = document.getElementById('statsModalBody');
                
                if (filteredEstimates.length === 0) {
                    modalBody.innerHTML = '<div class="loading">해당 조건의 견적이 없습니다.</div>';
                } else {
                    const table = `
                        <table class="table">
                            <thead>
                                <tr>
                                    <th>제목</th>
                                    <th>고객</th>
                                    <th>사업자</th>
                                    <th>금액</th>
                                    <th>상태</th>
                                    <th>생성일</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${filteredEstimates.map(estimate => `
                                    <tr>
                                        <td class="clickable-title" onclick="showEstimateDetail('${estimate.id}')" style="cursor: pointer; color: #1a73e8; text-decoration: underline;">${estimate.title || '제목 없음'}</td>
                                        <td>${estimate.customerName || '고객명 없음'}</td>
                                        <td>${estimate.businessName || '상호명 없음'}</td>
                                        <td>${estimate.estimatedPrice ? estimate.estimatedPrice.toLocaleString() + '원' : '금액 없음'}</td>
                                        <td>
                                            <span class="status-badge status-${estimate.status}">
                                                ${getStatusText(estimate.status)}
                                            </span>
                                        </td>
                                        <td>${new Date(estimate.createdAt).toLocaleDateString()}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    `;
                    modalBody.innerHTML = table;
                }

                document.getElementById('statsModal').style.display = 'block';
            } catch (error) {
                console.error('견적 상세 정보 로드 오류:', error);
                alert('견적 상세 정보를 불러오는데 실패했습니다.');
            }
        }

        // 수익 상세 정보 표시
        async function showRevenueDetails() {
            try {
                const estimates = await apiCall('/estimates');
                const completedEstimates = estimates.filter(e => e.status === 'completed');
                
                document.getElementById('statsModalTitle').textContent = '수익 상세 정보';
                const modalBody = document.getElementById('statsModalBody');
                
                if (completedEstimates.length === 0) {
                    modalBody.innerHTML = '<div class="loading">완료된 견적이 없어 수익 정보를 계산할 수 없습니다.</div>';
                } else {
                    const totalRevenue = completedEstimates.reduce((sum, e) => sum + ((e.estimatedPrice || 0) * 0.05), 0);
                    const averageRevenue = totalRevenue / completedEstimates.length;
                    
                    const table = `
                        <div class="detail-row">
                            <div class="detail-label">총 완료 견적:</div>
                            <div class="detail-value">${completedEstimates.length}건</div>
                        </div>
                        <div class="detail-row">
                            <div class="detail-label">총 수익:</div>
                            <div class="detail-value">${totalRevenue.toLocaleString()}원</div>
                        </div>
                        <div class="detail-row">
                            <div class="detail-label">평균 수익:</div>
                            <div class="detail-value">${averageRevenue.toLocaleString()}원</div>
                        </div>
                        <div class="detail-row">
                            <div class="detail-label">수수료율:</div>
                            <div class="detail-value">5%</div>
                        </div>
                        <hr style="margin: 1rem 0;">
                        <h4>완료된 견적 목록</h4>
                        <table class="table">
                            <thead>
                                <tr>
                                    <th>제목</th>
                                    <th>고객</th>
                                    <th>금액</th>
                                    <th>수익</th>
                                    <th>완료일</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${completedEstimates.map(estimate => `
                                    <tr>
                                        <td class="clickable-title" onclick="showEstimateDetail('${estimate.id}')" style="cursor: pointer; color: #1a73e8; text-decoration: underline;">${estimate.title || '제목 없음'}</td>
                                        <td>${estimate.customerName || '고객명 없음'}</td>
                                        <td>${estimate.estimatedPrice ? estimate.estimatedPrice.toLocaleString() + '원' : '금액 없음'}</td>
                                        <td>${((estimate.estimatedPrice || 0) * 0.05).toLocaleString()}원</td>
                                        <td>${new Date(estimate.updatedAt).toLocaleDateString()}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    `;
                    modalBody.innerHTML = table;
                }

                document.getElementById('statsModal').style.display = 'block';
            } catch (error) {
                console.error('수익 상세 정보 로드 오류:', error);
                alert('수익 상세 정보를 불러오는데 실패했습니다.');
            }
        }

        // 통계 모달 닫기
        function closeStatsModal() {
            document.getElementById('statsModal').style.display = 'none';
        }

        // 통계 숫자 클릭 이벤트 리스너 설정
        function setupStatsClickListeners() {
            // 사용자 통계 클릭 리스너
            const userStats = document.querySelectorAll('[data-type]');
            userStats.forEach(stat => {
                stat.addEventListener('click', () => {
                    const type = stat.getAttribute('data-type');
                    showUsersByType(type);
                });
            });

            // 견적 통계 클릭 리스너
            const estimateStats = document.querySelectorAll('[data-status]');
            estimateStats.forEach(stat => {
                stat.addEventListener('click', () => {
                    const status = stat.getAttribute('data-status');
                    showEstimatesByStatus(status);
                });
            });

            // 수익 통계 클릭 리스너
            const revenueStat = document.getElementById('totalRevenue');
            if (revenueStat) {
                revenueStat.addEventListener('click', showRevenueDetails);
            }
        }

// ===== 오더 현황 (마켓플레이스) =====
async function loadCalls() {
    try {
        console.log('[LOAD ORDERS] Fetching marketplace listings data...');
        allCalls = await apiCall('/calls');
        console.log('[LOAD ORDERS] Received:', allCalls.length, 'orders');
        callsPage = 1; // Reset to first page
        displayCalls();
    } catch (e) {
        console.error('오더 로드 오류:', e);
        const container = document.getElementById('callTableContainer');
        if (container) container.innerHTML = '<div class="error">오더 목록을 불러오는데 실패했습니다: ' + e.message + '</div>';
    }
}

function displayCalls() {
    const container = document.getElementById('callTableContainer');
    if (!container) return;
    if (!allCalls || allCalls.length === 0) {
        container.innerHTML = '<div class="loading">등록된 오더가 없습니다.</div>';
        return;
    }
    
    // 정렬 적용
    let sortedCalls = [...allCalls];
    if (callsSortColumn) {
        sortedCalls.sort((a, b) => {
            let aVal = a[callsSortColumn];
            let bVal = b[callsSortColumn];
            
            // 날짜 처리
            if (callsSortColumn === 'created_at' || callsSortColumn === 'claimed_at') {
                aVal = new Date(a[callsSortColumn] || 0).getTime();
                bVal = new Date(b[callsSortColumn] || 0).getTime();
            }
            
            // 금액 처리
            if (callsSortColumn === 'budget_amount') {
                aVal = a.budget_amount || 0;
                bVal = b.budget_amount || 0;
            }
            
            // 입찰 수 처리
            if (callsSortColumn === 'bid_count') {
                aVal = a.bid_count ?? 0;
                bVal = b.bid_count ?? 0;
            }
            
            // 문자열 비교
            if (typeof aVal === 'string') {
                aVal = (aVal || '').toLowerCase();
                bVal = (bVal || '').toLowerCase();
            }
            
            if (aVal < bVal) return callsSortDirection === 'asc' ? -1 : 1;
            if (aVal > bVal) return callsSortDirection === 'asc' ? 1 : -1;
            return 0;
        });
    }
    
    // 페이지네이션 적용
    const totalPages = Math.ceil(sortedCalls.length / callsPerPage);
    const startIdx = (callsPage - 1) * callsPerPage;
    const endIdx = startIdx + callsPerPage;
    const paginatedCalls = sortedCalls.slice(startIdx, endIdx);
    
    // 상태 매핑 함수
    const getCallStatusText = (status, claimedBy) => {
        if (claimedBy) return '완료';
        if (status === 'assigned') return '완료';
        if (status === 'completed') return '종료됨';
        if (status === 'cancelled') return '취소됨';
        if (status === 'created' || status === 'open') return '대기 중';
        return status || '대기 중';
    };
    
    const getStatusClass = (status, claimedBy) => {
        if (claimedBy || status === 'assigned') return 'success';
        if (status === 'completed') return 'completed';
        if (status === 'cancelled') return 'cancelled';
        return 'warning';
    };
    
    // 날짜 포맷 함수 (yyyy-MM-dd HH:mm)
    const formatDate = (dateStr) => {
        if (!dateStr) return '-';
        try {
            const date = new Date(dateStr);
            const year = date.getFullYear();
            const month = String(date.getMonth() + 1).padStart(2, '0');
            const day = String(date.getDate()).padStart(2, '0');
            const hours = String(date.getHours()).padStart(2, '0');
            const minutes = String(date.getMinutes()).padStart(2, '0');
            return `${year}-${month}-${day} ${hours}:${minutes}`;
        } catch (e) {
            return '-';
        }
    };
    
    // 통계 계산
    const total = sortedCalls.length;
    const pending = sortedCalls.filter(c => !c.claimed_by && c.status !== 'completed' && c.status !== 'cancelled' && c.status !== 'assigned').length;
    const completed = sortedCalls.filter(c => c.claimed_by || c.status === 'assigned').length;
    
    const table = `
        <table class="table">
            <thead>
                <tr>
                    <th class="sortable" data-column="title">제목</th>
                    <th class="sortable" data-column="location">위치</th>
                    <th class="sortable" data-column="category">카테고리</th>
                    <th class="sortable" data-column="budget_amount">예산</th>
                    <th class="sortable" data-column="status">상태</th>
                    <th class="sortable" data-column="bid_count">입찰</th>
                    <th>등록한 사업자</th>
                    <th>가져간 사업자</th>
                    <th class="sortable" data-column="claimed_at">입찰받은 날짜</th>
                    <th class="sortable" data-column="created_at">생성일</th>
                </tr>
            </thead>
            <tbody>
                ${paginatedCalls.map(item => {
                    const bidCount = item.bid_count ?? 0;
                    const isUnawarded = !item.claimed_by && item.status !== 'completed' && item.status !== 'cancelled' && item.status !== 'assigned';
                    const bidCell = isUnawarded
                        ? `<span style="font-weight: 600; color: ${bidCount > 0 ? 'var(--primary)' : '#9ca3af'};" title="클릭하여 입찰 목록 확인">${bidCount}건</span>`
                        : (bidCount > 0 ? `${bidCount}건` : '-');
                    return `
                    <tr style="cursor: pointer;" onclick="showCallDetail('${item.id}')">
                        <td><strong>${item.title || '-'}</strong></td>
                        <td>${item.location || item.region || '-'}</td>
                        <td>${item.category || '-'}</td>
                        <td>${typeof item.budget_amount === 'number' ? '₩' + item.budget_amount.toLocaleString('ko-KR') : '-'}</td>
                        <td>
                            <span class="status-badge status-${getStatusClass(item.status, item.claimed_by)}">
                                ${getCallStatusText(item.status, item.claimed_by)}
                            </span>
                        </td>
                        <td>${bidCell}</td>
                        <td>${item.owner_business_name || '-'}</td>
                        <td>${item.claimed_business_name || item.assigned_business_name || '<span style="color: #999;">-</span>'}</td>
                        <td>${item.claimed_at ? formatDate(item.claimed_at) : '<span style="color: #999;">-</span>'}</td>
                        <td>${formatDate(item.created_at)}</td>
                    </tr>
                `}).join('')}
            </tbody>
        </table>
        <div class="pagination">
            <button onclick="changeCallsPage(-1)" ${callsPage === 1 ? 'disabled' : ''}>이전</button>
            <span>페이지 ${callsPage} / ${totalPages} (전체 ${sortedCalls.length}건)</span>
            <button onclick="changeCallsPage(1)" ${callsPage >= totalPages ? 'disabled' : ''}>다음</button>
        </div>
    `;
    
    container.innerHTML = table;
    
    // 정렬 표시 업데이트
    if (callsSortColumn) {
        const headers = container.querySelectorAll('th');
        headers.forEach(th => {
            const col = th.getAttribute('data-column');
            if (col === callsSortColumn) {
                th.classList.add(callsSortDirection === 'asc' ? 'sort-asc' : 'sort-desc');
            }
        });
    }
    
    // 컬럼 헤더 클릭 이벤트 리스너
    const headers = container.querySelectorAll('th.sortable');
    headers.forEach(th => {
        th.addEventListener('click', () => {
            const column = th.getAttribute('data-column');
            if (callsSortColumn === column) {
                callsSortDirection = callsSortDirection === 'asc' ? 'desc' : 'asc';
            } else {
                callsSortColumn = column;
                callsSortDirection = 'asc';
            }
            displayCalls();
        });
    });
}

// 오더 페이지 변경
function changeCallsPage(delta) {
    const totalPages = Math.ceil(allCalls.length / callsPerPage);
    callsPage = Math.max(1, Math.min(callsPage + delta, totalPages));
    displayCalls();
}

// 오더 상세 + 프로세스 타임라인 보기
async function showCallDetail(jobId) {
    const modalBody = document.getElementById('callModalBody');
    const modalFooter = document.getElementById('callModalFooter');
    const modal = document.getElementById('callModal');

    // 모달 먼저 열고 로딩 표시
    modalBody.innerHTML = '<div class="loading"><div class="spinner"></div>프로세스 데이터를 불러오는 중...</div>';
    if (modalFooter) modalFooter.innerHTML = '<button class="btn btn-secondary" onclick="closeCallModal()">닫기</button>';
    modal.style.display = 'flex';

    const formatDate = (s) => {
        if (!s) return '-';
        try {
            const d = new Date(s);
            return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
        } catch (e) { return '-'; }
    };

    const STATUS_ORDER = ['created', 'open', 'assigned', 'in_progress', 'awaiting_confirmation', 'completed'];
    const isStatusAfter = (current, check) => {
        const ci = STATUS_ORDER.indexOf(current);
        const ci2 = STATUS_ORDER.indexOf(check);
        return ci >= 0 && ci2 >= 0 && ci >= ci2;
    };

    const STATUS_COLORS = {
        created: '#f59e0b', open: '#f59e0b', assigned: '#3b82f6',
        in_progress: '#3b82f6', awaiting_confirmation: '#8b5cf6',
        completed: '#10b981', cancelled: '#ef4444',
    };
    const STATUS_LABELS = {
        created: '입찰 대기', open: '공개됨', assigned: '낙찰됨',
        in_progress: '진행 중', awaiting_confirmation: '완료 확인 대기',
        completed: '완료', cancelled: '취소됨',
    };

    try {
        // 기본 목록 데이터 (이미 로드됨)
        const job = allCalls.find(c => c.id === jobId);
        if (!job) { modalBody.innerHTML = '<div class="error">오더를 찾을 수 없습니다.</div>'; return; }

        // 프로세스 상세 API 호출
        let processData = null;
        try {
            processData = await apiCall(`/listings/${jobId}/process`);
        } catch (e) {
            console.warn('[showCallDetail] 프로세스 API 실패, 기본 정보만 표시:', e.message);
        }

        const listing = processData?.listing || job;
        const bids = processData?.bids || [];
        const winnerBid = processData?.winner_bid || null;
        const reviews = processData?.reviews || [];
        const status = listing.status || 'created';
        const statusColor = STATUS_COLORS[status] || '#6b7280';
        const statusLabel = STATUS_LABELS[status] || status;
        const isUnawarded = !listing.claimed_by && status !== 'completed' && status !== 'cancelled';

        // 입찰 목록 HTML (미낙찰: 항상 표시, 낙찰됨: 입찰 있을 때만)
        const buildBidListHtml = () => {
            const showBids = isUnawarded || bids.length > 0;
            if (!showBids) return '';
            const borderColor = isUnawarded ? '#f59e0b' : '#e5e7eb';
            const bgColor = isUnawarded ? '#fffbeb' : 'white';
            const headerColor = isUnawarded ? '#92400e' : '#1e3a8a';
            return `
          <div style="background: ${bgColor}; border: 1px solid ${borderColor}; border-radius: 12px; padding: 1rem 1.25rem; margin-bottom: 1.25rem;">
            <h4 style="margin: 0 0 0.75rem 0; font-size: 0.9rem; font-weight: 700; color: ${headerColor}; display: flex; align-items: center; gap: 0.4rem;">
              <span class="material-icons" style="font-size: 1rem;">gavel</span>
              ${isUnawarded ? '미낙찰 오더 - 입찰 목록' : '입찰 현황'} (${bids.length}건)
            </h4>
            ${bids.length > 0 ? `
            <div style="overflow-x: auto;">
              <table style="width: 100%; border-collapse: collapse; font-size: 0.83rem;">
                <thead>
                  <tr style="background: #f9fafb; border-bottom: 1px solid #e5e7eb;">
                    <th style="padding: 6px 10px; text-align: left; font-weight: 600; color: #374151;">사업자</th>
                    <th style="padding: 6px 10px; text-align: right; font-weight: 600; color: #374151;">입찰금액</th>
                    <th style="padding: 6px 10px; text-align: left; font-weight: 600; color: #374151;">메시지</th>
                    <th style="padding: 6px 10px; text-align: left; font-weight: 600; color: #374151;">상태</th>
                    <th style="padding: 6px 10px; text-align: left; font-weight: 600; color: #374151;">입찰일</th>
                  </tr>
                </thead>
                <tbody>
                  ${bids.map(b => `
                    <tr style="border-bottom: 1px solid #f3f4f6; ${b.is_winner ? 'background: #f0fdf4;' : ''}">
                      <td style="padding: 7px 10px;">${b.is_winner ? '🏆 ' : ''}${b.bidder_name}</td>
                      <td style="padding: 7px 10px; text-align: right; font-weight: ${b.is_winner ? '700' : '400'};">
                        ${typeof b.bid_amount === 'number' ? '₩' + b.bid_amount.toLocaleString('ko-KR') : '-'}
                      </td>
                      <td style="padding: 7px 10px; max-width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" title="${(b.message || '').replace(/"/g, '&quot;')}">${b.message ? (b.message.length > 30 ? b.message.substring(0, 30) + '...' : b.message) : '-'}</td>
                      <td style="padding: 7px 10px;">
                        <span style="font-size: 0.75rem; padding: 2px 8px; border-radius: 10px; background: ${b.is_winner ? '#d1fae5' : '#f3f4f6'}; color: ${b.is_winner ? '#065f46' : '#6b7280'};">
                          ${b.is_winner ? '낙찰' : (b.status || '대기')}
                        </span>
                      </td>
                      <td style="padding: 7px 10px; color: #9ca3af;">${formatDate(b.created_at)}</td>
                    </tr>
                  `).join('')}
                </tbody>
              </table>
            </div>
            ` : `
            <div style="padding: 1rem; text-align: center; color: #6b7280; font-size: 0.9rem; background: white; border-radius: 8px; border: 1px dashed #e5e7eb;">
              아직 입찰이 없습니다.
            </div>
            `}
          </div>`;
        };

        // ── 오더 기본 정보 ──────────────────────────────────────────────
        let html = `
        <div style="font-family: inherit;">

          <!-- 기본 정보 카드 -->
          <div style="background: #f8faff; border: 1px solid #e0e8ff; border-radius: 12px; padding: 1rem 1.25rem; margin-bottom: 1.25rem;">
            <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 0.75rem;">
              <h3 style="margin: 0; font-size: 1rem; font-weight: 700; color: #1e3a8a;">${listing.title || '-'}</h3>
              <span style="background: ${statusColor}22; color: ${statusColor}; border: 1px solid ${statusColor}55;
                           padding: 3px 10px; border-radius: 20px; font-size: 0.75rem; font-weight: 600; white-space: nowrap; margin-left: 0.5rem;">
                ${statusLabel}
              </span>
            </div>
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; font-size: 0.85rem; color: #374151;">
              <div>📍 <b>지역:</b> ${listing.region || listing.location || '-'}</div>
              <div>🏷️ <b>카테고리:</b> ${listing.category || '-'}</div>
              <div>💰 <b>예산:</b> ${typeof listing.budget_amount === 'number' ? '₩' + listing.budget_amount.toLocaleString('ko-KR') : '-'}</div>
              <div>📅 <b>등록일:</b> ${formatDate(listing.createdat || listing.created_at)}</div>
              <div>👤 <b>등록 사업자:</b> ${listing.owner_name || listing.owner_business_name || '-'}</div>
              ${listing.owner_phone ? `<div>📞 ${listing.owner_phone}</div>` : '<div></div>'}
              ${listing.winner_name ? `<div>🏆 <b>낙찰 사업자:</b> ${listing.winner_name}</div>` : ''}
              ${listing.winner_phone ? `<div>📞 ${listing.winner_phone}</div>` : ''}
            </div>
            ${listing.description ? `<div style="margin-top: 0.75rem; padding-top: 0.75rem; border-top: 1px solid #e5e7eb; font-size: 0.85rem; color: #6b7280; line-height: 1.6;">${listing.description}</div>` : ''}
          </div>

          ${isUnawarded ? buildBidListHtml() : ''}

          <!-- 프로세스 타임라인 -->
          <div style="background: white; border: 1px solid #e5e7eb; border-radius: 12px; padding: 1rem 1.25rem; margin-bottom: 1.25rem;">
            <h4 style="margin: 0 0 1rem 0; font-size: 0.9rem; font-weight: 700; color: #1e3a8a; display: flex; align-items: center; gap: 0.4rem;">
              <span class="material-icons" style="font-size: 1rem;">timeline</span> 오더 프로세스
            </h4>
            ${buildProcessTimeline(status, listing, winnerBid, reviews, formatDate, isStatusAfter, STATUS_COLORS, STATUS_LABELS)}
          </div>

          ${!isUnawarded ? buildBidListHtml() : ''}

          <!-- 후기 -->
          ${reviews.length > 0 ? `
          <div style="background: #fffbeb; border: 1px solid #fde68a; border-radius: 12px; padding: 1rem 1.25rem; margin-bottom: 1.25rem;">
            <h4 style="margin: 0 0 0.75rem 0; font-size: 0.9rem; font-weight: 700; color: #92400e; display: flex; align-items: center; gap: 0.4rem;">
              <span class="material-icons" style="font-size: 1rem;">star</span> 완료 후기
            </h4>
            ${reviews.map(r => `
              <div style="background: white; border-radius: 8px; padding: 0.75rem 1rem; margin-bottom: 0.5rem;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
                  <div style="font-size: 0.83rem; color: #374151;">
                    <b>${r.reviewer_name}</b> → ${r.reviewee_name}
                  </div>
                  <div style="font-size: 0.8rem; color: #9ca3af;">${formatDate(r.created_at)}</div>
                </div>
                <div style="color: #f59e0b; font-size: 1.1rem; margin-bottom: 0.4rem;">
                  ${'★'.repeat(r.rating || 0)}${'☆'.repeat(5 - (r.rating || 0))}
                  <span style="font-size: 0.8rem; color: #6b7280; margin-left: 0.3rem;">${r.rating}점</span>
                </div>
                ${r.tags && r.tags.length > 0 ? `
                  <div style="display: flex; flex-wrap: wrap; gap: 0.3rem; margin-bottom: 0.4rem;">
                    ${r.tags.map(t => `<span style="background: #fef3c7; color: #92400e; padding: 2px 8px; border-radius: 10px; font-size: 0.75rem;">${t}</span>`).join('')}
                  </div>` : ''}
                ${r.comment ? `<div style="font-size: 0.85rem; color: #374151; line-height: 1.5;">"${r.comment}"</div>` : ''}
              </div>
            `).join('')}
          </div>
          ` : ''}

          <!-- 첨부 이미지 -->
          ${(() => {
            const mediaUrls = listing.media_urls || listing.jobs?.media_urls;
            if (!mediaUrls || !Array.isArray(mediaUrls) || mediaUrls.length === 0) return '';
            return `
            <div style="margin-bottom: 1.25rem;">
              <h4 style="margin: 0 0 0.5rem 0; font-size: 0.9rem; font-weight: 600; color: #374151;">📎 첨부 이미지</h4>
              <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
                ${mediaUrls.map(url => `<img src="${url}" style="width:100px;height:100px;object-fit:cover;border-radius:8px;cursor:pointer;" onclick="window.open('${url}','_blank')">`).join('')}
              </div>
            </div>`;
          })()}

          <!-- 상태 변경 -->
          <div style="background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 10px; padding: 0.875rem 1rem;">
            <span style="font-size: 0.85rem; font-weight: 600; color: #374151; margin-right: 0.5rem;">⚙️ 상태 변경:</span>
            <select id="orderStatusSelector" style="padding:0.4rem 0.75rem;border:1px solid var(--gray-300);border-radius:8px;font-size:0.875rem; margin-right: 0.5rem;">
              <option value="created" ${status === 'created' ? 'selected' : ''}>입찰 대기 (created)</option>
              <option value="open" ${status === 'open' ? 'selected' : ''}>공개됨 (open)</option>
              <option value="assigned" ${status === 'assigned' ? 'selected' : ''}>낙찰됨 (assigned)</option>
              <option value="in_progress" ${status === 'in_progress' ? 'selected' : ''}>진행 중 (in_progress)</option>
              <option value="awaiting_confirmation" ${status === 'awaiting_confirmation' ? 'selected' : ''}>완료 확인 대기</option>
              <option value="completed" ${status === 'completed' ? 'selected' : ''}>완료 (completed)</option>
              <option value="cancelled" ${status === 'cancelled' ? 'selected' : ''}>취소 (cancelled)</option>
            </select>
            <button class="btn btn-primary btn-sm" onclick="updateOrderStatus('${jobId}')">변경 저장</button>
          </div>

        </div>`;

        modalBody.innerHTML = html;
        document.getElementById('callModalTitle').textContent = `오더 상세: ${listing.title || ''}`;

        if (modalFooter) {
            modalFooter.innerHTML = `
                <button class="btn btn-secondary" onclick="closeCallModal()">닫기</button>
                <button class="btn btn-primary btn-sm" onclick="copyOrderShareText('${jobId}')">
                    <span class="material-icons" style="font-size: 0.9rem;">content_copy</span> 카카오톡 공유
                </button>
                <button class="btn btn-sm" onclick="copyOrderDeepLink('${jobId}')" style="background: var(--info); color: white;">
                    <span class="material-icons" style="font-size: 0.9rem;">link</span> 딥링크
                </button>
                <button class="btn btn-success btn-sm" onclick="sendOrderNotification('${jobId}')">
                    <span class="material-icons" style="font-size: 0.9rem;">send</span> 알림 발송
                </button>
                <button class="btn btn-danger btn-sm" onclick="deleteCall('${jobId}')">
                    <span class="material-icons" style="font-size: 0.9rem;">delete</span> 삭제
                </button>
            `;
        }

    } catch (error) {
        console.error('오더 상세 로드 오류:', error);
        modalBody.innerHTML = '<div class="error">오더 정보를 불러오는데 실패했습니다: ' + error.message + '</div>';
    }
}

// 프로세스 타임라인 HTML 생성 헬퍼
function buildProcessTimeline(status, listing, winnerBid, reviews, formatDate, isStatusAfter, STATUS_COLORS, STATUS_LABELS) {
    const steps = [
        {
            key: 'created',
            icon: 'add_circle',
            title: '오더 등록',
            color: '#1e3a8a',
            alwaysDone: true,
            time: listing.createdat || listing.created_at,
            detail: `${listing.owner_name || listing.owner_business_name || '사업자'} 님이 오더를 등록했습니다.`,
        },
        {
            key: 'assigned',
            icon: 'gavel',
            title: '낙찰',
            color: '#f59e0b',
            done: isStatusAfter(status, 'assigned'),
            active: status === 'created' || status === 'open',
            time: listing.claimed_at,
            detail: listing.claimed_by
                ? `${listing.winner_name || '사업자'} 님이 낙찰받았습니다.${winnerBid?.bid_amount ? '\n입찰금액: ₩' + winnerBid.bid_amount.toLocaleString('ko-KR') : ''}`
                : '아직 낙찰된 사업자가 없습니다.',
        },
        {
            key: 'in_progress',
            icon: 'construction',
            title: '진행 중',
            color: '#3b82f6',
            done: isStatusAfter(status, 'awaiting_confirmation'),
            active: status === 'assigned' || status === 'in_progress',
            time: null,
            detail: (status === 'assigned' || status === 'in_progress')
                ? `${listing.winner_name || '사업자'} 님이 작업을 진행하고 있습니다.`
                : isStatusAfter(status, 'awaiting_confirmation') ? '작업이 완료되었습니다.' : '아직 시작되지 않았습니다.',
        },
        {
            key: 'completed',
            icon: 'check_circle',
            title: '완료',
            color: '#10b981',
            done: status === 'completed' || status === 'awaiting_confirmation',
            active: status === 'awaiting_confirmation',
            time: (status === 'completed' || status === 'awaiting_confirmation') ? (listing.updatedat || listing.updated_at) : null,
            detail: status === 'completed' ? '오더가 최종 완료되었습니다.' :
                    status === 'awaiting_confirmation' ? '완료 확인을 기다리고 있습니다.' : '아직 완료되지 않았습니다.',
        },
        {
            key: 'review',
            icon: 'star',
            title: '후기',
            color: '#f59e0b',
            done: reviews.length > 0,
            active: status === 'completed' && reviews.length === 0,
            time: reviews.length > 0 ? reviews[0].created_at : null,
            detail: reviews.length > 0
                ? `★${reviews[0].rating}점  "${reviews[0].comment || ''}"${reviews[0].tags?.length > 0 ? '\n태그: ' + reviews[0].tags.join(', ') : ''}`
                : '아직 후기가 작성되지 않았습니다.',
        },
    ];

    return steps.map((step, i) => {
        const isDone = step.alwaysDone || step.done;
        const isActive = !isDone && step.active;
        const isLast = i === steps.length - 1;
        const color = isDone ? step.color : isActive ? step.color : '#d1d5db';
        const iconBg = isDone ? step.color : isActive ? step.color + '22' : '#f3f4f6';
        const iconColor = isDone ? 'white' : isActive ? step.color : '#9ca3af';

        return `
        <div style="display: flex; gap: 0; position: relative;">
          <!-- 아이콘 + 선 -->
          <div style="display: flex; flex-direction: column; align-items: center; margin-right: 14px; flex-shrink: 0;">
            <div style="width: 36px; height: 36px; border-radius: 50%; background: ${iconBg};
                        border: 2px solid ${isDone || isActive ? step.color : '#e5e7eb'};
                        display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
              <span class="material-icons" style="font-size: 1rem; color: ${iconColor};">${isDone ? 'check' : step.icon}</span>
            </div>
            ${!isLast ? `<div style="width: 2px; flex: 1; min-height: 12px; background: ${isDone ? step.color + '44' : '#f3f4f6'}; margin: 3px 0;"></div>` : ''}
          </div>
          <!-- 내용 -->
          <div style="padding-bottom: ${isLast ? '0' : '18px'}; flex: 1; min-width: 0;">
            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 3px;">
              <span style="font-size: 0.875rem; font-weight: 700; color: ${isDone || isActive ? '#111827' : '#9ca3af'};">${step.title}</span>
              ${isActive ? `<span style="background: ${step.color}22; color: ${step.color}; font-size: 0.7rem; font-weight: 600; padding: 1px 7px; border-radius: 10px;">현재 단계</span>` : ''}
            </div>
            ${step.time ? `<div style="font-size: 0.75rem; color: #9ca3af; margin-bottom: 3px;">${formatDate(step.time)}</div>` : ''}
            <div style="font-size: 0.8rem; color: ${isDone || isActive ? '#4b5563' : '#9ca3af'}; white-space: pre-line; line-height: 1.5;">${step.detail}</div>
          </div>
        </div>`;
    }).join('');
}

// 오더 삭제 함수
async function deleteCall(listingId) {
    if (!confirm('정말로 이 오더를 삭제하시겠습니까?\n\n⚠️ 관련된 입찰 정보도 함께 삭제됩니다.')) {
        return;
    }
    
    try {
        console.log('[deleteCall] 오더 삭제 시작:', listingId);
        
        // marketplace_listings 삭제 (CASCADE로 order_bids도 함께 삭제됨)
        const response = await apiCall(`/listings/${listingId}`, {
            method: 'DELETE'
        });
        
        if (response.success) {
            alert('오더가 삭제되었습니다.');
            closeCallModal();
            loadCalls();
            loadDashboard();
        } else {
            throw new Error(response.message || '삭제 실패');
        }
    } catch (error) {
        console.error('[deleteCall] 에러:', error);
        alert('오더 삭제에 실패했습니다: ' + error.message);
    }
}

// 오더 상태 업데이트
async function updateOrderStatus(listingId) {
    const select = document.getElementById('orderStatusSelector');
    if (!select) return;
    const newStatus = select.value;
    if (!newStatus) return;
    try {
        await apiCall(`/listings/${listingId}/status`, {
            method: 'PATCH',
            body: JSON.stringify({ status: newStatus })
        });
        alert('오더 상태가 변경되었습니다.');
        closeCallModal();
        loadCalls();
        loadDashboard();
    } catch (error) {
        alert('상태 변경에 실패했습니다: ' + error.message);
    }
}

// Call 모달 닫기
function closeCallModal() {
    document.getElementById('callModal').style.display = 'none';
}

// 오더 검색 필터
function filterOrders(query) {
    const statusFilter = document.getElementById('orderStatusFilter')?.value || '';
    const q = query.toLowerCase();
    const filtered = allCalls.filter(c => {
        const matchStatus = !statusFilter || c.status === statusFilter;
        const matchText = !q || (c.title || '').toLowerCase().includes(q) || (c.region || '').toLowerCase().includes(q);
        return matchStatus && matchText;
    });
    displayFilteredCalls(filtered);
}

function displayFilteredCalls(data) {
    const container = document.getElementById('callTableContainer');
    if (!container) return;
    const tmp = allCalls;
    allCalls = data;
    callsPage = 1;
    displayCalls();
    allCalls = tmp;
}

// ===== 게시물 관리 =====
let allPosts = [];

async function loadPosts() {
    try {
        const container = document.getElementById('postTableContainer');
        if (container) container.innerHTML = '<div class="loading"><div class="spinner"></div>로딩 중...</div>';
        allPosts = await apiCall('/posts');
        displayPosts(allPosts);
    } catch (e) {
        const container = document.getElementById('postTableContainer');
        if (container) container.innerHTML = '<div class="error">게시물 목록을 불러오는데 실패했습니다: ' + e.message + '</div>';
    }
}

function displayPosts(posts) {
    const container = document.getElementById('postTableContainer');
    if (!container) return;
    if (!posts || posts.length === 0) {
        container.innerHTML = '<div class="loading">등록된 게시물이 없습니다.</div>';
        return;
    }

    const formatDate = (s) => {
        if (!s) return '-';
        const d = new Date(s);
        return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
    };

    container.innerHTML = `
        <div class="table-container">
            <table class="table">
                <thead>
                    <tr>
                        <th>제목</th>
                        <th>작성자</th>
                        <th>카테고리</th>
                        <th>좋아요</th>
                        <th>댓글</th>
                        <th>작성일</th>
                        <th>관리</th>
                    </tr>
                </thead>
                <tbody>
                    ${posts.map(p => `
                        <tr>
                            <td style="cursor:pointer;color:#1a73e8;text-decoration:underline;" onclick="showPostDetail('${p.id}')">${(p.title || p.content || '').substring(0,40) || '제목 없음'}</td>
                            <td>${p.author_name || '알 수 없음'}</td>
                            <td>${p.category || '-'}</td>
                            <td>${p.likes_count || 0}</td>
                            <td>${p.comments_count || 0}</td>
                            <td>${formatDate(p.created_at)}</td>
                            <td>
                                <button class="btn btn-secondary btn-sm" onclick="showPostDetail('${p.id}')">상세</button>
                                <button class="btn btn-danger btn-sm" onclick="deletePost('${p.id}')">삭제</button>
                            </td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
        <div style="padding: 0.75rem; color: var(--gray-600); font-size: 0.875rem;">전체 ${posts.length}건</div>
    `;
}

function filterPosts(query) {
    const q = query.toLowerCase();
    const filtered = allPosts.filter(p =>
        (p.title || '').toLowerCase().includes(q) ||
        (p.content || '').toLowerCase().includes(q) ||
        (p.author_name || '').toLowerCase().includes(q)
    );
    displayPosts(filtered);
}

async function showPostDetail(postId) {
    const post = allPosts.find(p => p.id === postId);
    if (!post) {
        alert('게시물을 찾을 수 없습니다.');
        return;
    }
    const formatDate = (s) => s ? new Date(s).toLocaleString('ko-KR') : '-';

    document.getElementById('postModalTitle').textContent = '게시물 상세';
    document.getElementById('postModalBody').innerHTML = `
        <div class="detail-row"><div class="detail-label">제목</div><div class="detail-value">${post.title || '-'}</div></div>
        <div class="detail-row"><div class="detail-label">작성자</div><div class="detail-value">${post.author_name || '알 수 없음'} (${post.author_role || '-'})</div></div>
        <div class="detail-row"><div class="detail-label">카테고리</div><div class="detail-value">${post.category || '-'}</div></div>
        <div class="detail-row"><div class="detail-label">좋아요 / 댓글</div><div class="detail-value">${post.likes_count || 0}개 / ${post.comments_count || 0}개</div></div>
        <div class="detail-row"><div class="detail-label">작성일</div><div class="detail-value">${formatDate(post.created_at)}</div></div>
        <hr style="margin: 1rem 0;">
        <div style="padding: 1rem; background: var(--gray-50); border-radius: 8px; white-space: pre-wrap; line-height: 1.7;">${post.content || '내용 없음'}</div>
    `;
    document.getElementById('postModalFooter').innerHTML = `
        <button class="btn btn-secondary" onclick="closePostModal()">닫기</button>
        <button class="btn btn-danger" onclick="deletePost('${postId}'); closePostModal();">삭제</button>
    `;
    document.getElementById('postModal').style.display = 'flex';
}

async function deletePost(postId) {
    if (!confirm('이 게시물을 삭제하시겠습니까?')) return;
    try {
        await apiCall(`/posts/${postId}`, { method: 'DELETE' });
        alert('게시물이 삭제되었습니다.');
        loadPosts();
    } catch (e) {
        alert('삭제 실패: ' + e.message);
    }
}

function closePostModal() {
    document.getElementById('postModal').style.display = 'none';
}

// ===== 채팅 현황 =====
let allChats = [];

async function loadChats() {
    try {
        const container = document.getElementById('chatTableContainer');
        if (container) container.innerHTML = '<div class="loading"><div class="spinner"></div>로딩 중...</div>';
        allChats = await apiCall('/chats');
        displayChats(allChats);
    } catch (e) {
        const container = document.getElementById('chatTableContainer');
        if (container) container.innerHTML = '<div class="error">채팅방 목록을 불러오는데 실패했습니다: ' + e.message + '</div>';
    }
}

function displayChats(chats) {
    const container = document.getElementById('chatTableContainer');
    if (!container) return;
    if (!chats || chats.length === 0) {
        container.innerHTML = '<div class="loading">개설된 채팅방이 없습니다.</div>';
        return;
    }

    const formatDate = (s) => {
        if (!s) return '-';
        const d = new Date(s);
        return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
    };

    container.innerHTML = `
        <div class="table-container">
            <table class="table">
                <thead>
                    <tr>
                        <th>참여자 A</th>
                        <th>참여자 B</th>
                        <th>마지막 메시지</th>
                        <th>마지막 활동</th>
                        <th>개설일</th>
                        <th>관리</th>
                    </tr>
                </thead>
                <tbody>
                    ${chats.map(c => `
                        <tr>
                            <td>${c.participant_a_name || '-'} <small style="color:#999;">(${c.participant_a_role === 'business' ? '사업자' : '고객'})</small></td>
                            <td>${c.participant_b_name || '-'} <small style="color:#999;">(${c.participant_b_role === 'business' ? '사업자' : '고객'})</small></td>
                            <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${c.last_message || '-'}</td>
                            <td>${formatDate(c.last_message_at || c.updated_at)}</td>
                            <td>${formatDate(c.created_at)}</td>
                            <td>
                                <button class="btn btn-secondary btn-sm" onclick="showChatDetail('${c.id}')">메시지 보기</button>
                                <button class="btn btn-danger btn-sm" onclick="deleteChat('${c.id}')">삭제</button>
                            </td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
        <div style="padding: 0.75rem; color: var(--gray-600); font-size: 0.875rem;">전체 ${chats.length}개 채팅방</div>
    `;
}

function filterChats(query) {
    const q = query.toLowerCase();
    const filtered = allChats.filter(c =>
        (c.participant_a_name || '').toLowerCase().includes(q) ||
        (c.participant_b_name || '').toLowerCase().includes(q)
    );
    displayChats(filtered);
}

async function showChatDetail(roomId) {
    const room = allChats.find(c => c.id === roomId);
    if (!room) return;

    document.getElementById('chatModalTitle').textContent = `채팅방: ${room.participant_a_name} ↔ ${room.participant_b_name}`;
    document.getElementById('chatModalBody').innerHTML = '<div class="loading"><div class="spinner"></div>메시지 로딩 중...</div>';
    document.getElementById('chatModal').style.display = 'flex';

    try {
        const messages = await apiCall(`/chats/${roomId}/messages`);
        const formatDate = (s) => s ? new Date(s).toLocaleString('ko-KR') : '-';

        const aId = room.participant_a;
        const msgHtml = messages.map(m => {
            const isA = m.sender_id === aId;
            const senderLabel = isA ? room.participant_a_name : room.participant_b_name;
            return `
                <div style="margin-bottom:0.75rem;display:flex;flex-direction:column;align-items:${isA ? 'flex-start' : 'flex-end'};">
                    <div style="font-size:0.75rem;color:var(--gray-500);margin-bottom:0.25rem;">${senderLabel} · ${formatDate(m.created_at)}</div>
                    <div style="max-width:75%;padding:0.6rem 0.9rem;border-radius:12px;background:${isA ? 'var(--gray-100)' : '#1a73e8'};color:${isA ? 'inherit' : 'white'};word-break:break-word;">
                        ${m.image_url ? `<img src="${m.image_url}" style="max-width:200px;border-radius:8px;display:block;margin-bottom:0.25rem;" onclick="window.open('${m.image_url}','_blank')">` : ''}
                        ${m.content || ''}
                    </div>
                </div>
            `;
        }).join('');

        document.getElementById('chatModalBody').innerHTML = messages.length === 0
            ? '<div style="text-align:center;color:var(--gray-500);padding:2rem;">메시지가 없습니다.</div>'
            : `<div style="padding: 0.5rem;">${msgHtml}</div>`;
    } catch (e) {
        document.getElementById('chatModalBody').innerHTML = '<div class="error">메시지를 불러오는데 실패했습니다: ' + e.message + '</div>';
    }

    document.getElementById('chatModalFooter').innerHTML = `
        <button class="btn btn-secondary" onclick="closeChatModal()">닫기</button>
        <button class="btn btn-danger" onclick="deleteChat('${roomId}'); closeChatModal();">채팅방 삭제</button>
    `;
}

async function deleteChat(roomId) {
    if (!confirm('이 채팅방과 모든 메시지를 삭제하시겠습니까?')) return;
    try {
        await apiCall(`/chats/${roomId}`, { method: 'DELETE' });
        alert('채팅방이 삭제되었습니다.');
        loadChats();
    } catch (e) {
        alert('삭제 실패: ' + e.message);
    }
}

function closeChatModal() {
    document.getElementById('chatModal').style.display = 'none';
}

// 오더에 대해 사업자들에게 알림 발송
async function sendOrderNotification(orderId) {
    const customMessage = prompt(
        '사업자들에게 보낼 메시지를 입력하세요:\n\n' +
        '(비워두면 기본 메시지가 전송됩니다)'
    );
    
    // 취소 버튼을 누른 경우
    if (customMessage === null) {
        return;
    }
    
    try {
        console.log('[sendOrderNotification] 알림 발송 시작:', orderId);
        
        // 로딩 표시
        const loadingDiv = document.createElement('div');
        loadingDiv.id = 'notification-loading';
        loadingDiv.innerHTML = `
            <div style="position: fixed; top: 0; left: 0; width: 100%; height: 100%; 
                        background: rgba(0,0,0,0.5); display: flex; align-items: center; 
                        justify-content: center; z-index: 10000;">
                <div style="background: white; padding: 2rem; border-radius: 12px; text-align: center;">
                    <div class="spinner" style="margin: 0 auto 1rem;"></div>
                    <div>사업자들에게 알림을 발송하는 중...</div>
                </div>
            </div>
        `;
        document.body.appendChild(loadingDiv);
        
        const response = await apiCall(`/orders/${orderId}/notify`, {
            method: 'POST',
            body: JSON.stringify({
                message: customMessage?.trim() || null,
                targetRegion: true,  // 오더의 지역에 해당하는 사업자
                targetCategory: true, // 오더의 카테고리에 해당하는 사업자
            })
        });
        
        // 로딩 제거
        document.getElementById('notification-loading')?.remove();
        
        if (response.success) {
            alert(`✅ 성공!\n\n${response.message}\n\n성공: ${response.sent}명\n실패: ${response.failed}명\n전체: ${response.total}명`);
        } else {
            alert('❌ 알림 발송에 실패했습니다');
        }
    } catch (error) {
        console.error('[sendOrderNotification] 에러:', error);
        document.getElementById('notification-loading')?.remove();
        alert('알림 발송에 실패했습니다: ' + error.message);
    }
}

// 오더를 카카오톡으로 공유
async function shareOrderToKakao(orderId) {
    try {
        const calls = await apiCall('/calls');
        const order = calls.find(c => c.id === orderId);
        
        if (!order) {
            alert('오더 정보를 찾을 수 없습니다.');
            return;
        }
        
        console.log('[shareOrderToKakao] 오더 정보:', order);
        
        // 예산 포맷팅
        const budgetText = order.budget_amount 
            ? `\n💰 견적가: ${order.budget_amount.toLocaleString('ko-KR')}원`
            : '';
        
        // 카카오톡 공유 템플릿
        const template = {
            objectType: 'feed',
            content: {
                title: `🔧 ${order.title || '오더'}`,
                description: `📍 지역: ${order.location || order.region || '지역 미지정'}\n🏷️ 카테고리: ${order.category || '일반'}${budgetText}\n\n${order.description || '상세 설명이 없습니다.'}`,
                imageUrl: order.media_urls && order.media_urls.length > 0 
                    ? order.media_urls[0]
                    : 'https://allsuri.app/assets/images/logo.png',
                link: {
                    mobileWebUrl: 'https://play.google.com/store/apps/details?id=com.ononcompany.allsuri',
                    webUrl: 'https://play.google.com/store/apps/details?id=com.ononcompany.allsuri',
                },
            },
            buttons: [
                {
                    title: '앱에서 보기',
                    link: {
                        mobileWebUrl: 'https://play.google.com/store/apps/details?id=com.ononcompany.allsuri',
                        webUrl: 'https://play.google.com/store/apps/details?id=com.ononcompany.allsuri',
                    },
                },
            ],
        };
        
        // Kakao SDK 확인
        if (!window.Kakao || !Kakao.isInitialized()) {
            alert('Kakao SDK가 초기화되지 않았습니다.\n\n관리자에게 문의하세요.');
            return;
        }
        
        // 카카오톡 공유 실행
        Kakao.Share.sendDefault(template);
        
        console.log('[shareOrderToKakao] 카카오톡 공유 완료');
    } catch (error) {
        console.error('[shareOrderToKakao] 에러:', error);
        alert('카카오톡 공유에 실패했습니다: ' + error.message);
    }
}

// 오더 공유 텍스트 복사 (딥링크 포함, 카카오톡이 자동으로 링크 버튼 생성)
async function copyOrderShareText(orderId) {
    try {
        const calls = await apiCall('/calls');
        const order = calls.find(c => c.id === orderId);
        
        if (!order) {
            alert('오더 정보를 찾을 수 없습니다.');
            return;
        }
        
        // 예산 포맷팅
        const budgetText = order.budget_amount 
            ? `\n💰 예산: ${order.budget_amount.toLocaleString('ko-KR')}원`
            : '';
        
        // HTTPS 링크 생성 (카카오톡이 자동으로 링크 버튼 생성)
        const webLink = `https://api.allsuri.app/order/${orderId}`;
        
        // 공유 텍스트 생성 (HTTPS 링크 포함)
        const shareText = `🔧 새로운 오더 등록!\n\n` +
            `📌 ${order.title || '오더'}\n` +
            `📍 지역: ${order.location || order.region || '지역 미지정'}\n` +
            `🏷️ 카테고리: ${order.category || '일반'}${budgetText}\n\n` +
            `${order.description || ''}\n\n` +
            `${webLink}`;
        
        // 클립보드에 복사
        await navigator.clipboard.writeText(shareText);
        
        alert('✅ 공유 텍스트가 클립보드에 복사되었습니다!\n\n카카오톡에 붙여넣으면 링크가 버튼으로 표시됩니다.');
    } catch (error) {
        console.error('[copyOrderShareText] 에러:', error);
        alert('텍스트 복사에 실패했습니다: ' + error.message);
    }
}

// 오더 딥링크 복사 (관리자 전용)
async function copyOrderDeepLink(orderId) {
    try {
        const deepLink = `allsuri://order/${orderId}`;
        
        // 클립보드에 복사
        await navigator.clipboard.writeText(deepLink);
        
        alert('✅ 딥링크가 클립보드에 복사되었습니다!\n\n' + deepLink + '\n\n이 링크를 공유하면 앱이 설치된 사용자는 해당 오더로 바로 이동합니다.');
    } catch (error) {
        console.error('[copyOrderDeepLink] 에러:', error);
        alert('링크 복사에 실패했습니다: ' + error.message);
    }
}

// module.exports = router; // 브라우저 환경에서 불필요 (제거)

// 견적 상세 보기 함수
async function showEstimateDetail(estimateId) {
    try {
        // allEstimates에서 해당 견적을 찾거나 API로 다시 가져오기
        let estimate = allEstimates.find(e => e.id === estimateId);
        
        if (!estimate) {
            alert('견적 정보를 찾을 수 없습니다.');
            return;
        }
        
        const modalBody = document.getElementById('estimateModalBody');
        
        let detailHtml = `
            <div class="detail-group">
                <div class="detail-item">
                    <span class="detail-label">제목:</span>
                    <span class="detail-value">${estimate.title || estimate.description || '-'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">고객명:</span>
                    <span class="detail-value">${estimate.customerName || estimate.customername || '-'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">상호명:</span>
                    <span class="detail-value">${estimate.businessName || estimate.businessname || '-'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">견적 금액:</span>
                    <span class="detail-value">${typeof (estimate.amount || estimate.estimatedPrice) === 'number' ? '₩' + (estimate.amount || estimate.estimatedPrice).toLocaleString('ko-KR') : '-'}</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">상태:</span>
                    <span class="detail-value"><span class="status-badge status-${estimate.status}">${getStatusText(estimate.status)}</span></span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">생성일:</span>
                    <span class="detail-value">${formatDate(estimate.createdAt || estimate.createdat)}</span>
                </div>
        `;
        
        // 추가 정보가 있으면 표시
        if (estimate.orderid) {
            detailHtml += `
                <div class="detail-item">
                    <span class="detail-label">주문 ID:</span>
                    <span class="detail-value">${estimate.orderid}</span>
                </div>
            `;
        }
        
        if (estimate.customerid) {
            detailHtml += `
                <div class="detail-item">
                    <span class="detail-label">고객 ID:</span>
                    <span class="detail-value">${estimate.customerid}</span>
                </div>
            `;
        }
        
        if (estimate.businessid) {
            detailHtml += `
                <div class="detail-item">
                    <span class="detail-label">사업자 ID:</span>
                    <span class="detail-value">${estimate.businessid}</span>
                </div>
            `;
        }
        
        // 상세 설명이 있으면 추가
        if (estimate.details || estimate.description) {
            detailHtml += `
                <div class="detail-item" style="grid-column: 1 / -1;">
                    <span class="detail-label">상세 설명:</span>
                    <span class="detail-value">${estimate.details || estimate.description}</span>
                </div>
            `;
        }
        
        // 미디어 URL이 있으면 추가
        if (estimate.mediaurls && Array.isArray(estimate.mediaurls) && estimate.mediaurls.length > 0) {
            detailHtml += `
                <div class="detail-item" style="grid-column: 1 / -1;">
                    <span class="detail-label">첨부 이미지:</span>
                    <div style="display: flex; gap: 0.5rem; flex-wrap: wrap; margin-top: 0.5rem;">
                        ${estimate.mediaurls.map(url => `
                            <img src="${url}" alt="견적 이미지" style="width: 120px; height: 120px; object-fit: cover; border-radius: 8px; cursor: pointer;" onclick="window.open('${url}', '_blank')">
                        `).join('')}
                    </div>
                </div>
            `;
        }
        
        detailHtml += `</div>`;
        
        modalBody.innerHTML = detailHtml;
        document.getElementById('estimateModal').style.display = 'flex';
    } catch (error) {
        console.error('견적 상세 정보 로드 오류:', error);
        alert('견적 상세 정보를 불러오는데 실패했습니다.');
    }
}

// 견적 모달 닫기
function closeEstimateModal() {
    document.getElementById('estimateModal').style.display = 'none';
}

// ===== 광고 관리 =====

async function loadAds() {
    try {
        const ads = await apiCall('/ads');
        displayAds(ads);
    } catch (e) {
        console.error('광고 로드 오류:', e);
        const c = document.getElementById('adsTableContainer');
        if (c) c.innerHTML = '<div class="error">광고 목록을 불러오는데 실패했습니다: ' + e.message + '</div>';
    }
}

function getLocationLabel(location) {
    const labels = {
        'home_banner': '📱 홈 화면 배너',
        'dashboard_ad_1': '🎯 대시보드 광고 1',
        'dashboard_ad_2': '🎯 대시보드 광고 2',
    };
    return labels[location] || location;
}

function displayAds(items) {
    const c = document.getElementById('adsTableContainer');
    if (!c) return;
    if (!items || items.length === 0) {
        c.innerHTML = `
            <div class="empty-state">
                <span class="material-icons">campaign</span>
                <p>등록된 광고가 없습니다</p>
                <button class="btn btn-primary" id="firstAdBtn">
                    <span class="material-icons">add</span>
                    첫 광고 추가하기
                </button>
            </div>
        `;
        // 이벤트 리스너 추가
        const firstAdBtn = document.getElementById('firstAdBtn');
        if (firstAdBtn) {
            firstAdBtn.addEventListener('click', () => showAdModal());
        }
        return;
    }
    
    // 위치별로 그룹화
    const byLocation = {
        'home_banner': [],
        'dashboard_ad_1': [],
        'dashboard_ad_2': []
    };
    
    items.forEach(ad => {
        if (byLocation[ad.location]) {
            byLocation[ad.location].push(ad);
        }
    });
    
    let html = '';
    
    // 각 위치별로 표시
    Object.entries(byLocation).forEach(([location, ads]) => {
        html += `
            <div style="margin-bottom: 2rem;">
                <h3 style="margin-bottom: 1rem; color: var(--gray-700); display: flex; align-items: center; gap: 0.5rem;">
                    ${getLocationLabel(location)}
                    ${ads.length === 0 ? '<span style="font-size: 0.875rem; color: var(--gray-500);">(광고 없음)</span>' : ''}
                </h3>
                ${ads.length > 0 ? `
                    <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem;">
                        ${ads.map(ad => `
                            <div style="border: 1px solid var(--gray-200); border-radius: 12px; padding: 1rem; background: white;">
                                ${ad.image_url ? `
                                    <img src="${ad.image_url}" alt="${ad.title}" 
                                        style="width: 100%; height: 120px; object-fit: cover; border-radius: 8px; margin-bottom: 0.75rem;"
                                        onerror="this.src='data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%22100%22 height=%22100%22%3E%3Crect fill=%22%23ddd%22 width=%22100%22 height=%22100%22/%3E%3Ctext x=%2250%25%22 y=%2250%25%22 text-anchor=%22middle%22 dy=%22.3em%22 fill=%22%23999%22%3E이미지 없음%3C/text%3E%3C/svg%3E'">
                                ` : `
                                    <div style="width: 100%; height: 120px; background: var(--gray-100); border-radius: 8px; display: flex; align-items: center; justify-content: center; margin-bottom: 0.75rem; color: var(--gray-400);">
                                        <span class="material-icons" style="font-size: 3rem;">image</span>
                                    </div>
                                `}
                                <h4 style="font-size: 1rem; margin-bottom: 0.5rem; color: var(--gray-900);">${ad.title || '제목 없음'}</h4>
                                ${ad.link_url ? `
                                    <p style="font-size: 0.75rem; color: var(--info); margin-bottom: 0.5rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                                        🔗 ${ad.link_url}
                                    </p>
                                ` : ''}
                                <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 0.75rem;">
                                    <span class="status-badge ${ad.is_active ? 'approved' : 'rejected'}">
                                        ${ad.is_active ? '✅ 활성' : '❌ 비활성'}
                                    </span>
                                    <div style="display: flex; gap: 0.5rem;">
                                        <button class="btn btn-secondary btn-sm edit-ad-btn" data-ad='${JSON.stringify(ad).replace(/'/g, "&apos;")}'>
                                            <span class="material-icons" style="font-size: 1rem;">edit</span>
                                        </button>
                                        <button class="btn btn-danger btn-sm delete-ad-btn" data-ad-id="${ad.id}">
                                            <span class="material-icons" style="font-size: 1rem;">delete</span>
                                        </button>
                                    </div>
                                </div>
                            </div>
                        `).join('')}
                    </div>
                ` : `
                    <div style="padding: 2rem; text-align: center; background: var(--gray-50); border-radius: 8px; color: var(--gray-500);">
                        이 위치에 광고가 없습니다. 
                        <button class="btn btn-primary btn-sm add-ad-btn" data-location="${location}" style="margin-left: 0.5rem;">
                            추가하기
                        </button>
                    </div>
                `}
            </div>
        `;
    });
    
    c.innerHTML = html;
    
    // "추가하기" 버튼들에 이벤트 리스너 추가
    const addBtns = c.querySelectorAll('.add-ad-btn');
    addBtns.forEach(btn => {
        btn.addEventListener('click', function() {
            const location = this.getAttribute('data-location');
            showAdModal(location);
        });
    });
    
    // "수정" 버튼들에 이벤트 리스너 추가
    const editBtns = c.querySelectorAll('.edit-ad-btn');
    editBtns.forEach(btn => {
        btn.addEventListener('click', function() {
            const adData = this.getAttribute('data-ad');
            try {
                const ad = JSON.parse(adData.replace(/&apos;/g, "'"));
                editAd(ad);
            } catch (e) {
                console.error('광고 데이터 파싱 실패:', e);
                alert('광고 정보를 불러올 수 없습니다.');
            }
        });
    });
    
    // "삭제" 버튼들에 이벤트 리스너 추가
    const deleteBtns = c.querySelectorAll('.delete-ad-btn');
    deleteBtns.forEach(btn => {
        btn.addEventListener('click', function() {
            const adId = this.getAttribute('data-ad-id');
            deleteAd(adId);
        });
    });
}

function showAdModal(defaultLocation = 'home_banner') {
    currentEditingAd = null;
    document.getElementById('adModalTitle').textContent = '새 광고 추가';
    document.getElementById('adId').value = '';
    document.getElementById('adTitle').value = '';
    document.getElementById('adLink').value = '';
    document.getElementById('adLocation').value = defaultLocation;
    document.getElementById('adActive').value = 'true';
    document.getElementById('adImageUrl').value = '';
    document.getElementById('adImagePreview').innerHTML = '';
    updateLocationGuide(defaultLocation);
    document.getElementById('adModal').style.display = 'block';
}

function editAd(ad) {
    try { 
        ad = (typeof ad === 'string') ? JSON.parse(ad) : ad; 
    } catch(_) {}
    
    currentEditingAd = ad;
    document.getElementById('adModalTitle').textContent = '광고 수정';
    document.getElementById('adId').value = ad.id || '';
    document.getElementById('adTitle').value = ad.title || '';
    document.getElementById('adLink').value = ad.link_url || '';
    document.getElementById('adLocation').value = ad.location || 'home_banner';
    document.getElementById('adActive').value = ad.is_active ? 'true' : 'false';
    document.getElementById('adImageUrl').value = ad.image_url || '';
    
    // 이미지 미리보기
    if (ad.image_url) {
        document.getElementById('adImagePreview').innerHTML = `
            <img src="${ad.image_url}" style="width: 100%; max-height: 200px; object-fit: cover; border-radius: 8px; margin-top: 0.5rem;">
        `;
    }
    
    updateLocationGuide(ad.location || 'home_banner');
    document.getElementById('adModal').style.display = 'block';
}

function updateLocationGuide(location) {
    const guides = {
        'home_banner': '📱 홈 화면 상단 배너 (권장: 1200×400px, 3:1 비율)',
        'dashboard_ad_1': '🎯 대시보드 광고 슬라이드 1번 (권장: 800×200px, 4:1 비율)',
        'dashboard_ad_2': '🎯 대시보드 광고 슬라이드 2번 (권장: 800×200px, 4:1 비율)'
    };
    const guideEl = document.getElementById('locationGuide');
    if (guideEl) {
        guideEl.textContent = guides[location] || '';
    }
}

function previewAdImage() {
    const url = document.getElementById('adImageUrl').value;
    const preview = document.getElementById('adImagePreview');
    
    if (url) {
        preview.innerHTML = `
            <img src="${url}" 
                style="width: 100%; max-height: 200px; object-fit: cover; border-radius: 8px; margin-top: 0.5rem;"
                onerror="this.parentElement.innerHTML='<p style=\\'color: var(--danger);\\'>이미지를 불러올 수 없습니다</p>'">
        `;
    } else {
        preview.innerHTML = '';
    }
}

async function saveAd() {
    const id = document.getElementById('adId').value;
    const title = document.getElementById('adTitle').value.trim();
    const link = document.getElementById('adLink').value.trim();
    const location = document.getElementById('adLocation').value;
    const isActive = document.getElementById('adActive').value === 'true';
    const imageUrl = document.getElementById('adImageUrl').value.trim();
    
    if (!title) {
        alert('제목을 입력해주세요');
        return;
    }
    
    const payload = {
        title,
        link_url: link || null,
        location,
        is_active: isActive,
        image_url: imageUrl || '',
    };
    
    try {
        if (id) {
            // 수정
            await apiCall(`/ads/${id}`, { 
                method: 'PUT', 
                body: JSON.stringify(payload) 
            });
            alert('광고가 수정되었습니다');
        } else {
            // 신규 생성 - 서버에서 createdat을 자동으로 추가하므로 제거
            await apiCall('/ads', { 
                method: 'POST', 
                body: JSON.stringify(payload) 
            });
            alert('광고가 추가되었습니다');
        }
        closeAdModal();
        loadAds();
    } catch (e) {
        console.error('광고 저장 실패:', e);
        alert('광고 저장에 실패했습니다: ' + e.message);
    }
}

async function deleteAd(id) {
    if (!confirm('정말로 이 광고를 삭제하시겠습니까?')) return;
    try {
        await apiCall(`/ads/${id}`, { method: 'DELETE' });
        alert('광고가 삭제되었습니다');
        loadAds();
    } catch (e) {
        console.error('광고 삭제 실패:', e);
        alert('광고 삭제에 실패했습니다');
    }
}

function closeAdModal() {
    document.getElementById('adModal').style.display = 'none';
    currentEditingAd = null;
}

// ===== 공지 배너 관리 =====
async function loadAnnouncements() {
    try {
        const container = document.getElementById('announcementTableContainer');
        if (container) container.innerHTML = '<div class="loading"><div class="spinner"></div>로딩 중...</div>';
        allAnnouncements = await apiCall('/announcements');
        displayAnnouncements();
    } catch (e) {
        const container = document.getElementById('announcementTableContainer');
        if (container) container.innerHTML = '<div class="error">공지 목록을 불러오는데 실패했습니다: ' + e.message + '</div>';
    }
}

function displayAnnouncements() {
    const container = document.getElementById('announcementTableContainer');
    if (!container) return;

    const formatDate = (s) => {
        if (!s) return '-';
        return new Date(s).toLocaleString('ko-KR', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
    };

    if (allAnnouncements.length === 0) {
        container.innerHTML = `
            <div style="text-align:center;padding:3rem;color:var(--gray-500);">
                <span class="material-icons" style="font-size:2.5rem;display:block;margin-bottom:0.5rem;">notifications_off</span>
                등록된 공지가 없습니다.<br>
                <button class="btn btn-primary btn-sm" style="margin-top:1rem;" id="btnNewAnnouncementEmpty">
                    <span class="material-icons">add</span> 첫 공지 만들기
                </button>
            </div>`;
        const btn = document.getElementById('btnNewAnnouncementEmpty');
        if (btn) btn.addEventListener('click', showAnnouncementModal);
        return;
    }

    container.innerHTML = `
        <div class="table-container">
            <table class="table">
                <thead>
                    <tr>
                        <th>미리보기</th>
                        <th>내용</th>
                        <th>활성</th>
                        <th>노출 기간</th>
                        <th>등록일</th>
                        <th>관리</th>
                    </tr>
                </thead>
                <tbody>
                    ${allAnnouncements.map(a => `
                        <tr>
                            <td>
                                <div style="background:${a.bg_color};color:${a.text_color};padding:5px 10px;border-radius:6px;font-size:0.78rem;font-weight:500;white-space:nowrap;max-width:200px;overflow:hidden;text-overflow:ellipsis;">
                                    ${a.message || ''}
                                </div>
                            </td>
                            <td style="max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${a.message || '-'}</td>
                            <td>
                                <span style="background:${a.is_active ? '#d1fae5' : '#f3f4f6'};color:${a.is_active ? '#065f46' : '#6b7280'};padding:2px 8px;border-radius:10px;font-size:0.75rem;font-weight:600;">
                                    ${a.is_active ? '활성' : '비활성'}
                                </span>
                            </td>
                            <td style="font-size:0.78rem;color:var(--gray-600);">
                                ${a.start_at ? formatDate(a.start_at) : '즉시'} ~<br>
                                ${a.end_at ? formatDate(a.end_at) : '무기한'}
                            </td>
                            <td style="font-size:0.78rem;color:var(--gray-500);">${formatDate(a.createdat)}</td>
                            <td>
                                <button class="btn btn-secondary btn-sm" style="margin-right:4px;" onclick="editAnnouncement('${a.id}')">수정</button>
                                <button class="btn ${a.is_active ? 'btn-warning' : 'btn-success'} btn-sm" style="margin-right:4px;" onclick="toggleAnnouncement('${a.id}', ${a.is_active})">
                                    ${a.is_active ? '비활성화' : '활성화'}
                                </button>
                                <button class="btn btn-danger btn-sm" onclick="deleteAnnouncement('${a.id}')">삭제</button>
                            </td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
        <div style="padding:0.75rem;color:var(--gray-500);font-size:0.85rem;">전체 ${allAnnouncements.length}개</div>
    `;
}

function showAnnouncementModal() {
    currentEditingAnnouncement = null;
    document.getElementById('announcementModalTitle').textContent = '새 공지 배너';
    document.getElementById('announcementId').value = '';
    document.getElementById('announcementMessage').value = '';
    document.getElementById('announcementBgColor').value = '#1E3A8A';
    document.getElementById('announcementBgColorText').value = '#1E3A8A';
    document.getElementById('announcementTextColor').value = '#FFFFFF';
    document.getElementById('announcementTextColorText').value = '#FFFFFF';
    document.getElementById('announcementStartAt').value = '';
    document.getElementById('announcementEndAt').value = '';
    document.getElementById('announcementIsActive').checked = true;
    document.getElementById('announcementIsDismissible').checked = true;
    updateAnnouncementPreview();
    document.getElementById('announcementModal').style.display = 'flex';
}

function editAnnouncement(id) {
    const a = allAnnouncements.find(x => x.id === id);
    if (!a) return;
    currentEditingAnnouncement = a;

    const toLocalDatetime = (iso) => {
        if (!iso) return '';
        return new Date(iso).toISOString().slice(0, 16);
    };

    document.getElementById('announcementModalTitle').textContent = '공지 수정';
    document.getElementById('announcementId').value = a.id;
    document.getElementById('announcementMessage').value = a.message || '';
    document.getElementById('announcementBgColor').value = a.bg_color || '#1E3A8A';
    document.getElementById('announcementBgColorText').value = a.bg_color || '#1E3A8A';
    document.getElementById('announcementTextColor').value = a.text_color || '#FFFFFF';
    document.getElementById('announcementTextColorText').value = a.text_color || '#FFFFFF';
    document.getElementById('announcementStartAt').value = toLocalDatetime(a.start_at);
    document.getElementById('announcementEndAt').value = toLocalDatetime(a.end_at);
    document.getElementById('announcementIsActive').checked = !!a.is_active;
    document.getElementById('announcementIsDismissible').checked = !!a.is_dismissible;
    updateAnnouncementPreview();
    document.getElementById('announcementModal').style.display = 'flex';
}

function closeAnnouncementModal() {
    document.getElementById('announcementModal').style.display = 'none';
    currentEditingAnnouncement = null;
}

function updateAnnouncementPreview() {
    const preview = document.getElementById('announcementPreview');
    const previewText = document.getElementById('previewText');
    if (!preview || !previewText) return;
    const bg = document.getElementById('announcementBgColor')?.value || '#1E3A8A';
    const tc = document.getElementById('announcementTextColor')?.value || '#FFFFFF';
    const msg = document.getElementById('announcementMessage')?.value || '공지 내용이 여기 표시됩니다';
    preview.style.background = bg;
    preview.style.color = tc;
    previewText.textContent = msg;
}

function syncColor(type) {
    if (type === 'bg') {
        const val = document.getElementById('announcementBgColorText').value;
        if (/^#[0-9A-Fa-f]{6}$/.test(val)) {
            document.getElementById('announcementBgColor').value = val;
            updateAnnouncementPreview();
        }
    } else {
        const val = document.getElementById('announcementTextColorText').value;
        if (/^#[0-9A-Fa-f]{6}$/.test(val)) {
            document.getElementById('announcementTextColor').value = val;
            updateAnnouncementPreview();
        }
    }
}

function applyPreset(bg, tc) {
    document.getElementById('announcementBgColor').value = bg;
    document.getElementById('announcementBgColorText').value = bg;
    document.getElementById('announcementTextColor').value = tc;
    document.getElementById('announcementTextColorText').value = tc;
    updateAnnouncementPreview();
}

async function saveAnnouncement() {
    const message = document.getElementById('announcementMessage').value.trim();
    if (!message) { alert('공지 내용을 입력해주세요.'); return; }

    const toISO = (localStr) => localStr ? new Date(localStr).toISOString() : null;

    const payload = {
        message,
        bg_color: document.getElementById('announcementBgColor').value || '#1E3A8A',
        text_color: document.getElementById('announcementTextColor').value || '#FFFFFF',
        is_active: document.getElementById('announcementIsActive').checked,
        is_dismissible: document.getElementById('announcementIsDismissible').checked,
        start_at: toISO(document.getElementById('announcementStartAt').value),
        end_at: toISO(document.getElementById('announcementEndAt').value),
    };

    const id = document.getElementById('announcementId').value;
    try {
        if (id) {
            await apiCall(`/announcements/${id}`, { method: 'PUT', body: JSON.stringify(payload) });
            alert('공지가 수정되었습니다.');
        } else {
            await apiCall('/announcements', { method: 'POST', body: JSON.stringify(payload) });
            alert('공지가 등록되었습니다.');
        }
        closeAnnouncementModal();
        loadAnnouncements();
    } catch (e) {
        alert('저장 실패: ' + e.message);
    }
}

async function toggleAnnouncement(id, currentActive) {
    try {
        await apiCall(`/announcements/${id}`, {
            method: 'PUT',
            body: JSON.stringify({ is_active: !currentActive })
        });
        loadAnnouncements();
    } catch (e) {
        alert('상태 변경 실패: ' + e.message);
    }
}

async function deleteAnnouncement(id) {
    if (!confirm('이 공지를 삭제하시겠습니까?')) return;
    try {
        await apiCall(`/announcements/${id}`, { method: 'DELETE' });
        loadAnnouncements();
    } catch (e) {
        alert('삭제 실패: ' + e.message);
    }
}

// ============================================================
// ===== 웹 견적 관리 (Web Orders) =====
// ============================================================

async function loadWebOrders() {
    const container = document.getElementById('webOrderTableContainer');
    if (!container) return;
    container.innerHTML = '<div class="loading"><div class="spinner"></div>로딩 중...</div>';
    try {
        const status = document.getElementById('webOrderStatusFilter')?.value || '';
        const params = status ? `?status=${encodeURIComponent(status)}` : '';
        const data = await apiCall(`/web-orders${params}`);
        allWebOrders = Array.isArray(data) ? data : [];
        filterWebOrders();
    } catch (e) {
        container.innerHTML = `<div style="padding:2rem;text-align:center;color:var(--danger);">불러오기 실패: ${e.message}</div>`;
    }
}

function filterWebOrders() {
    const container = document.getElementById('webOrderTableContainer');
    if (!container) return;
    const q = (document.getElementById('webOrderSearchInput')?.value || '').toLowerCase();
    const status = document.getElementById('webOrderStatusFilter')?.value || '';
    let filtered = allWebOrders;
    if (status) filtered = filtered.filter(o => o.status === status);
    if (q) filtered = filtered.filter(o =>
        (o.title || '').toLowerCase().includes(q) ||
        (o.customerName || o.customername || '').toLowerCase().includes(q) ||
        (o.address || '').toLowerCase().includes(q)
    );
    renderWebOrderTable(filtered, container);
}

function renderWebOrderTable(orders, container) {
    if (!orders.length) {
        container.innerHTML = '<div style="padding:3rem;text-align:center;color:var(--gray-500);">견적 요청이 없습니다.</div>';
        return;
    }
    const statusBadge = (s) => {
        const map = {
            pending: ['대기중', 'warning'],
            in_progress: ['진행중', 'info'],
            completed: ['완료', 'success'],
            cancelled: ['취소', 'danger'],
        };
        const [label, cls] = map[s] || [s, ''];
        const colors = { warning: '#f59e0b', info: '#3b82f6', success: '#10b981', danger: '#ef4444', '': '#6b7280' };
        const bgs = { warning: '#fffbeb', info: '#eff6ff', success: '#ecfdf5', danger: '#fef2f2', '': '#f9fafb' };
        return `<span style="padding:0.25rem 0.75rem;border-radius:20px;font-size:0.75rem;font-weight:600;background:${bgs[cls]};color:${colors[cls]};">${label}</span>`;
    };
    const rows = orders.map(o => {
        const name = o.customerName || o.customername || '-';
        const phone = o.customerPhone || o.customerphone || '-';
        const date = (o.createdAt || o.createdat || '').slice(0, 10);
        const hasRating = o.adminRating;
        return `<tr style="cursor:pointer;" onclick="openWebOrderModal('${o.id}')">
            <td style="padding:0.875rem 0.5rem;" onclick="event.stopPropagation()">
                <input type="checkbox" class="web-order-chk" data-id="${o.id}" onchange="updateWebOrderBulkBar()" style="width:16px;height:16px;cursor:pointer;">
            </td>
            <td style="padding:0.875rem 0.75rem;">${statusBadge(o.status)}</td>
            <td style="padding:0.875rem 0.75rem;font-weight:500;">${o.title || '-'}</td>
            <td style="padding:0.875rem 0.75rem;">${o.category || '-'}</td>
            <td style="padding:0.875rem 0.75rem;">${name}</td>
            <td style="padding:0.875rem 0.75rem;">
                <a href="tel:${phone}" onclick="event.stopPropagation()" style="color:var(--primary);text-decoration:none;font-weight:500;">${phone}</a>
            </td>
            <td style="padding:0.875rem 0.75rem;max-width:180px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${o.address || '-'}</td>
            <td style="padding:0.875rem 0.75rem;color:var(--gray-500);font-size:0.875rem;">${date}</td>
            <td style="padding:0.875rem 0.75rem;">
                ${hasRating ? `<span style="color:#f59e0b;">★ ${o.adminRating}</span>` : (o.status === 'in_progress' ? '<span style="color:var(--primary);font-size:0.8rem;">평점 미입력</span>' : '')}
            </td>
            <td style="padding:0.875rem 0.75rem;" onclick="event.stopPropagation()">
                <button onclick="deleteSingleWebOrder('${o.id}')" style="padding:0.3rem 0.6rem;background:none;border:1px solid var(--danger);color:var(--danger);border-radius:6px;font-size:0.75rem;cursor:pointer;">삭제</button>
            </td>
        </tr>`;
    }).join('');

    container.innerHTML = `
        <div id="webOrderBulkBar" style="display:none;padding:0.75rem 1rem;background:var(--primary-light);border-radius:8px;margin-bottom:0.75rem;display:flex;align-items:center;justify-content:space-between;">
            <span id="webOrderSelectedCount" style="font-size:0.875rem;font-weight:600;color:var(--primary);">0건 선택됨</span>
            <button onclick="bulkDeleteWebOrders()" style="padding:0.4rem 1rem;background:var(--danger);color:white;border:none;border-radius:8px;font-size:0.875rem;font-weight:600;cursor:pointer;">선택 삭제</button>
        </div>
        <div style="overflow-x:auto;">
            <table style="width:100%;border-collapse:collapse;">
                <thead>
                    <tr style="background:var(--gray-50);border-bottom:2px solid var(--gray-200);">
                        <th style="padding:0.75rem 0.5rem;"><input type="checkbox" id="webOrderChkAll" onchange="toggleAllWebOrders(this.checked)" style="width:16px;height:16px;cursor:pointer;"></th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">상태</th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">제목</th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">카테고리</th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">고객명</th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">전화번호</th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">주소</th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">접수일</th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">평점</th>
                        <th style="padding:0.75rem 0.75rem;text-align:left;font-size:0.8rem;color:var(--gray-600);">삭제</th>
                    </tr>
                </thead>
                <tbody id="webOrderTbody">
                    ${rows}
                </tbody>
            </table>
        </div>
        <div style="padding:0.75rem 1rem;color:var(--gray-500);font-size:0.875rem;border-top:1px solid var(--gray-100);">
            총 ${orders.length}건
        </div>`;
}

function toggleAllWebOrders(checked) {
    document.querySelectorAll('.web-order-chk').forEach(chk => chk.checked = checked);
    updateWebOrderBulkBar();
}

function updateWebOrderBulkBar() {
    const checked = document.querySelectorAll('.web-order-chk:checked');
    const bar = document.getElementById('webOrderBulkBar');
    const countEl = document.getElementById('webOrderSelectedCount');
    if (!bar) return;
    if (checked.length > 0) {
        bar.style.display = 'flex';
        countEl.textContent = `${checked.length}건 선택됨`;
    } else {
        bar.style.display = 'none';
    }
}

async function deleteSingleWebOrder(orderId) {
    if (!confirm('이 견적 요청을 삭제하시겠습니까?\n관련 입찰 견적도 함께 삭제됩니다.')) return;
    try {
        await apiCall(`/web-orders/${orderId}`, { method: 'DELETE' });
        allWebOrders = allWebOrders.filter(o => o.id !== orderId);
        filterWebOrders();
    } catch (e) {
        alert('삭제 실패: ' + e.message);
    }
}

async function bulkDeleteWebOrders() {
    const checked = document.querySelectorAll('.web-order-chk:checked');
    const ids = Array.from(checked).map(c => c.dataset.id);
    if (!ids.length) return;
    if (!confirm(`선택한 ${ids.length}건을 삭제하시겠습니까?\n관련 입찰 견적도 함께 삭제됩니다.`)) return;
    try {
        await apiCall('/web-orders', {
            method: 'DELETE',
            body: JSON.stringify({ ids }),
        });
        allWebOrders = allWebOrders.filter(o => !ids.includes(o.id));
        filterWebOrders();
    } catch (e) {
        alert('삭제 실패: ' + e.message);
    }
}

function openWebOrderModal(orderId) {
    const order = allWebOrders.find(o => o.id === orderId);
    if (!order) return;
    currentWebOrderId = orderId;
    selectedRating = 0;

    document.getElementById('webOrderModalTitle').textContent = `웹 견적 #${orderId.slice(0, 8)}`;

    // 견적 정보 렌더링
    const name = order.customerName || order.customername || '-';
    const phone = order.customerPhone || order.customerphone || '-';
    const email = order.customerEmail || order.customeremail || '-';
    const isMatched = order.status === 'in_progress' || order.status === 'completed';
    const images = Array.isArray(order.images) && order.images.length
        ? order.images.map(img => `<img src="${img}" style="width:80px;height:80px;object-fit:cover;border-radius:6px;cursor:pointer;" onclick="window.open('${img}','_blank')">`).join('')
        : '';

    document.getElementById('webOrderDetail').innerHTML = `
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;">
            <div style="background:var(--gray-50);border-radius:10px;padding:1.25rem;">
                <div style="font-weight:600;margin-bottom:0.75rem;display:flex;align-items:center;gap:0.5rem;">
                    <span class="material-icons" style="color:var(--primary);font-size:1.2rem;">person</span>
                    고객 정보
                </div>
                <table style="width:100%;font-size:0.875rem;border-collapse:collapse;">
                    <tr><td style="padding:0.3rem 0;color:var(--gray-600);width:80px;">사장님 성함</td><td style="padding:0.3rem 0;font-weight:500;">${name}</td></tr>
                    <tr><td style="padding:0.3rem 0;color:var(--gray-600);">전화</td><td style="padding:0.3rem 0;"><a href="tel:${phone}" style="color:var(--primary);font-weight:600;">${phone}</a></td></tr>
                    <tr><td style="padding:0.3rem 0;color:var(--gray-600);">이메일</td><td style="padding:0.3rem 0;">${email}</td></tr>
                </table>
            </div>
            <div style="background:var(--gray-50);border-radius:10px;padding:1.25rem;">
                <div style="font-weight:600;margin-bottom:0.75rem;display:flex;align-items:center;gap:0.5rem;">
                    <span class="material-icons" style="color:var(--primary);font-size:1.2rem;">assignment</span>
                    견적 정보
                </div>
                <table style="width:100%;font-size:0.875rem;border-collapse:collapse;">
                    <tr><td style="padding:0.3rem 0;color:var(--gray-600);width:70px;">제목</td><td style="padding:0.3rem 0;font-weight:500;">${order.title || '-'}</td></tr>
                    <tr><td style="padding:0.3rem 0;color:var(--gray-600);">카테고리</td><td style="padding:0.3rem 0;">${order.category || '-'}</td></tr>
                    <tr><td style="padding:0.3rem 0;color:var(--gray-600);">주소</td><td style="padding:0.3rem 0;">${order.address || '-'}</td></tr>
                    <tr><td style="padding:0.3rem 0;color:var(--gray-600);">방문일</td><td style="padding:0.3rem 0;">${(order.visitDate || order.visitdate || '').slice(0, 10)}</td></tr>
                    <tr><td style="padding:0.3rem 0;color:var(--gray-600);">상태</td><td style="padding:0.3rem 0;">${order.status}</td></tr>
                </table>
            </div>
        </div>
        ${order.description ? `<div style="margin-top:1rem;padding:1rem;background:var(--gray-50);border-radius:8px;font-size:0.875rem;"><b>요청 내용:</b><br>${order.description}</div>` : ''}
        ${images ? `<div style="margin-top:1rem;display:flex;gap:0.5rem;flex-wrap:wrap;">${images}</div>` : ''}
        ${order.adminNotes ? `<div style="margin-top:0.75rem;padding:0.75rem;background:#fffbeb;border-radius:8px;font-size:0.875rem;color:#92400e;"><b>관리자 메모:</b> ${order.adminNotes}</div>` : ''}
        ${isMatched ? `<div style="margin-top:0.75rem;padding:0.75rem;background:var(--success-light);border-radius:8px;font-size:0.875rem;color:#166534;"><b>✅ 매칭 완료</b> - 사업자가 앱 '내 공사 관리'에서 확인 가능합니다.</div>` : ''}
        ${order.adminRating ? `<div style="margin-top:0.75rem;padding:0.75rem;background:#fffbeb;border-radius:8px;font-size:0.875rem;"><b>평점:</b> ${'★'.repeat(order.adminRating)}${'☆'.repeat(5 - order.adminRating)} (${order.adminRating}/5) ${order.adminRatingComment ? `<br><span style="color:var(--gray-600);">${order.adminRatingComment}</span>` : ''}</div>` : ''}
    `;

    // 매칭 섹션 표시/숨김
    const matchSection = document.getElementById('webOrderMatchSection');
    const ratingSection = document.getElementById('webOrderRatingSection');
    if (isMatched) {
        matchSection.style.display = 'none';
        ratingSection.style.display = 'block';
    } else {
        matchSection.style.display = 'block';
        ratingSection.style.display = 'none';
    }

    // 기본값 세팅
    document.getElementById('matchAmount').value = order.estimatedPrice || '';
    document.getElementById('matchNotes').value = '';
    document.getElementById('bizSearchInput').value = '';
    document.getElementById('bizCategoryFilter').value = order.category || '';
    document.getElementById('bizSearchResults').innerHTML = '<div style="padding:2rem;text-align:center;color:var(--gray-500);font-size:0.875rem;">사업자를 검색하세요</div>';
    document.getElementById('ratingComment').value = '';
    setRating(0);

    document.getElementById('webOrderModal').classList.add('active');
}

function closeWebOrderModal() {
    document.getElementById('webOrderModal').classList.remove('active');
    currentWebOrderId = null;
}

function debounceSearchBiz() {
    clearTimeout(bizSearchTimer);
    bizSearchTimer = setTimeout(searchBusinessesForMatch, 500);
}

async function searchBusinessesForMatch() {
    const q = document.getElementById('bizSearchInput')?.value || '';
    const category = document.getElementById('bizCategoryFilter')?.value || '';
    const resultsDiv = document.getElementById('bizSearchResults');
    resultsDiv.innerHTML = '<div style="padding:1.5rem;text-align:center;color:var(--gray-500);">검색 중...</div>';
    try {
        const params = new URLSearchParams();
        if (q) params.append('q', q);
        if (category) params.append('category', category);
        const businesses = await apiCall(`/web-orders/businesses?${params.toString()}`);
        renderBizSearchResults(Array.isArray(businesses) ? businesses : []);
    } catch (e) {
        resultsDiv.innerHTML = `<div style="padding:1.5rem;text-align:center;color:var(--danger);">오류: ${e.message}</div>`;
    }
}

function renderBizSearchResults(businesses) {
    const resultsDiv = document.getElementById('bizSearchResults');
    if (!businesses.length) {
        resultsDiv.innerHTML = '<div style="padding:2rem;text-align:center;color:var(--gray-500);">검색 결과가 없습니다.</div>';
        return;
    }
    resultsDiv.innerHTML = businesses.map(b => {
        const dispName = b.businessname || b.name || '-';
        const phone = b.phonenumber || '-';
        const region = b.region || '-';
        const cat = b.category || '-';
        const awarded = b.projects_awarded_count || 0;
        return `<div style="display:flex;align-items:center;justify-content:space-between;padding:0.875rem 1rem;border-bottom:1px solid var(--gray-100);transition:background 0.15s;"
                     onmouseover="this.style.background='var(--gray-50)'" onmouseout="this.style.background=''">
            <div>
                <div style="font-weight:600;font-size:0.9rem;">${dispName}</div>
                <div style="font-size:0.8rem;color:var(--gray-500);margin-top:0.25rem;">
                    📞 ${phone} &nbsp;|&nbsp; 📍 ${region} &nbsp;|&nbsp; 🔧 ${cat} &nbsp;|&nbsp; 🏆 낙찰 ${awarded}건
                </div>
            </div>
            <button class="btn btn-primary btn-sm" onclick="confirmMatch('${b.id}','${(dispName).replace(/'/g, "\\'")}')">
                <span class="material-icons" style="font-size:0.9rem;">handshake</span>매칭
            </button>
        </div>`;
    }).join('');
}

function confirmMatch(businessId, businessName) {
    const amount = document.getElementById('matchAmount')?.value || '';
    const notes = document.getElementById('matchNotes')?.value || '';
    if (!confirm(`[${businessName}] 에게 이 견적을 매칭하시겠습니까?\n\n매칭 후 해당 사업자의 앱 '내 공사 관리'에 표시됩니다.`)) return;
    matchWebOrder(currentWebOrderId, businessId, businessName, amount, notes);
}

async function matchWebOrder(orderId, businessId, businessName, amount, notes) {
    try {
        const result = await apiCall(`/web-orders/${orderId}/match`, {
            method: 'POST',
            body: JSON.stringify({ businessId, businessName, amount: parseFloat(amount) || 0, notes }),
        });
        alert(`✅ ${result.message || '매칭 완료'}\n사업자 앱 '내 공사 관리'에서 확인 가능합니다.`);
        closeWebOrderModal();
        await loadWebOrders();
    } catch (e) {
        alert(`❌ 매칭 실패: ${e.message}`);
    }
}

function setRating(val) {
    selectedRating = val;
    const stars = document.querySelectorAll('#ratingStars .star-btn');
    const labels = ['', '매우 불만족', '불만족', '보통', '만족', '매우 만족'];
    stars.forEach((s, i) => {
        s.style.color = i < val ? '#f59e0b' : 'var(--gray-300)';
    });
    const label = document.getElementById('ratingLabel');
    if (label) label.textContent = val ? labels[val] : '';
}

async function submitWebOrderRating() {
    if (!selectedRating) { alert('평점을 선택해 주세요.'); return; }
    if (!currentWebOrderId) return;
    const comment = document.getElementById('ratingComment')?.value || '';
    if (!confirm(`평점 ${selectedRating}점을 저장하시겠습니까?`)) return;
    try {
        const result = await apiCall(`/web-orders/${currentWebOrderId}/rate`, {
            method: 'POST',
            body: JSON.stringify({ rating: selectedRating, comment }),
        });
        alert(`✅ ${result.message || '평점이 저장되었습니다.'}`);
        closeWebOrderModal();
        await loadWebOrders();
    } catch (e) {
        alert(`❌ 평점 저장 실패: ${e.message}`);
    }
}

// ===== 초기화 및 전체 로드 =====
async function loadAll() {
    try {
        await loadDashboard();
        console.log('✅ Dashboard loaded successfully');
    } catch (error) {
        console.error('❌ Error loading dashboard:', error);
    }
}

// ══════════════════════════════════════════════════════════════
// 웹 콘텐츠 관리 (Web Content Management)
// ══════════════════════════════════════════════════════════════

// ── 웹 설정 로드 ──────────────────────────────────────────────
async function loadWebContent() {
    // 사이트 설정
    try {
        const settingsRes = await apiCall('/web-content/settings');
        const settings = Array.isArray(settingsRes) ? settingsRes : [];
        settings.forEach(s => {
            const el = document.getElementById(`setting_${s.key}`);
            if (!el) return;
            if (el.tagName === 'SELECT') el.value = s.value;
            else el.value = s.value || '';
        });
    } catch (e) {
        console.warn('[loadWebContent] 설정 로드 실패 (무시):', e.message);
    }

    // 광고 목록
    try {
        const adsRes = await apiCall('/web-content/ads');
        const ads = Array.isArray(adsRes) ? adsRes : [];
        renderWebAds(ads);
    } catch (e) {
        console.warn('[loadWebContent] 광고 로드 실패 (무시):', e.message);
        renderWebAds([]);
    }

    // 추천 업체 (독립 로드 – 위 항목 실패해도 반드시 실행)
    await loadFeaturedBusinesses();
}

function renderWebAds(ads) {
    const container = document.getElementById('webAdsContainer');
    if (!container) return;
    if (!ads.length) {
        container.innerHTML = '<div style="text-align:center;padding:2rem;color:var(--gray-400);">등록된 광고 배너가 없습니다.</div>';
        return;
    }
    const positionLabel = { home_top: '홈 상단', home_middle: '홈 중간', home_bottom: '홈 하단', sidebar: '사이드바' };
    container.innerHTML = `
        <table class="table">
            <thead><tr><th>미리보기</th><th>제목</th><th>위치</th><th>상태</th><th>관리</th></tr></thead>
            <tbody>
                ${ads.map(a => `
                    <tr>
                        <td style="width:80px;">
                            ${a.image_url ? `<img src="${a.image_url}" style="width:72px;height:40px;object-fit:cover;border-radius:4px;" onerror="this.style.display='none'"/>` : '-'}
                        </td>
                        <td>
                            <div style="font-weight:600;">${a.title || '-'}</div>
                            ${a.link_url ? `<div style="font-size:0.8rem;color:var(--gray-500);">${a.link_url.substring(0, 40)}...</div>` : ''}
                        </td>
                        <td><span style="background:#eff6ff;color:#1d4ed8;padding:0.2rem 0.6rem;border-radius:4px;font-size:0.8rem;">${positionLabel[a.position] || a.position}</span></td>
                        <td><span style="background:${a.is_active ? '#dcfce7' : '#fee2e2'};color:${a.is_active ? '#166534' : '#991b1b'};padding:0.2rem 0.6rem;border-radius:4px;font-size:0.8rem;">${a.is_active ? '활성' : '비활성'}</span></td>
                        <td>
                            <button class="btn btn-secondary btn-sm" onclick="editWebAd('${a.id}')">수정</button>
                            <button class="btn btn-sm" style="background:#fee2e2;color:#991b1b;border-color:#fca5a5;" onclick="deleteWebAd('${a.id}')">삭제</button>
                        </td>
                    </tr>
                `).join('')}
            </tbody>
        </table>`;
}

// ── 웹 설정 저장 ──────────────────────────────────────────────
async function saveWebSettings() {
    const keys = ['hero_title', 'hero_subtitle', 'contact_phone', 'notice_banner', 'notice_banner_active'];
    const rows = keys.map(k => ({
        key: k,
        value: document.getElementById(`setting_${k}`)?.value || '',
    }));
    try {
        await apiCall('/web-content/settings', { method: 'POST', body: JSON.stringify({ settings: rows }) });
        showToast('✅ 사이트 설정이 저장되었습니다.');
    } catch (e) {
        alert('저장 실패: ' + e.message);
    }
}

// ── 웹 광고 모달 ──────────────────────────────────────────────
let _editingWebAdId = null;

function openWebAdModal(id = null) {
    _editingWebAdId = id;
    document.getElementById('webAdModalTitle').textContent = id ? '웹 광고 배너 수정' : '웹 광고 배너 추가';
    if (!id) {
        ['webAdId', 'webAdTitle', 'webAdImageUrl', 'webAdLinkUrl'].forEach(eid => {
            const el = document.getElementById(eid);
            if (el) el.value = '';
        });
        document.getElementById('webAdPosition').value = 'home_top';
        document.getElementById('webAdIsActive').value = 'true';
        document.getElementById('webAdImagePreview').innerHTML = '';
    }
    document.getElementById('webAdModal').classList.add('active');
}

async function editWebAd(id) {
    const res = await apiCall(`/web-content/ads/${id}`);
    const a = res?.ad || (Array.isArray(res) ? res[0] : null);
    if (!a) return;
    document.getElementById('webAdId').value = a.id;
    document.getElementById('webAdTitle').value = a.title || '';
    document.getElementById('webAdImageUrl').value = a.image_url || '';
    document.getElementById('webAdLinkUrl').value = a.link_url || '';
    document.getElementById('webAdPosition').value = a.position || 'home_top';
    document.getElementById('webAdIsActive').value = String(a.is_active !== false);
    previewWebAdImage();
    openWebAdModal(id);
}

function closeWebAdModal() {
    document.getElementById('webAdModal').classList.remove('active');
}

function previewWebAdImage() {
    const url = document.getElementById('webAdImageUrl')?.value;
    const prev = document.getElementById('webAdImagePreview');
    if (!prev) return;
    prev.innerHTML = url
        ? `<img src="${url}" style="max-width:100%;max-height:120px;border-radius:8px;border:1px solid var(--gray-200);" onerror="this.style.display='none'"/>`
        : '';
}

async function saveWebAd() {
    const id = document.getElementById('webAdId')?.value;
    const payload = {
        title: document.getElementById('webAdTitle').value,
        image_url: document.getElementById('webAdImageUrl').value,
        link_url: document.getElementById('webAdLinkUrl').value,
        position: document.getElementById('webAdPosition').value,
        is_active: document.getElementById('webAdIsActive').value === 'true',
    };
    if (id) payload.id = id;

    try {
        await apiCall('/web-content/ads', { method: 'POST', body: JSON.stringify(payload) });
        closeWebAdModal();
        showToast('✅ 광고 배너가 저장되었습니다.');
        await loadWebContent();
    } catch (e) {
        alert('저장 실패: ' + e.message);
    }
}

async function deleteWebAd(id) {
    if (!confirm('이 광고 배너를 삭제하시겠습니까?')) return;
    await apiCall(`/web-content/ads/${id}`, { method: 'DELETE' });
    showToast('🗑️ 삭제되었습니다.');
    await loadWebContent();
}

function showToast(msg) {
    const div = document.createElement('div');
    div.textContent = msg;
    div.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:#1e3a8a;color:#fff;padding:0.75rem 1.5rem;border-radius:12px;font-size:0.9rem;z-index:9999;box-shadow:0 4px 16px rgba(0,0,0,0.2);';
    document.body.appendChild(div);
    setTimeout(() => div.remove(), 3000);
}

// ══════════════════════════════════════════════════════════════
// 푸시 알림 발송
// ══════════════════════════════════════════════════════════════

let _selectedPushUserIds = [];

function togglePushTarget() {
    const val = document.querySelector('input[name="pushTarget"]:checked')?.value;
    const area = document.getElementById('pushSpecificArea');
    if (area) area.style.display = val === 'specific' ? 'block' : 'none';
    if (val === 'all') {
        _selectedPushUserIds = [];
        const list = document.getElementById('pushSelectedBizList');
        if (list) list.innerHTML = '';
    }
}

// 앱 업데이트 알림 체크박스: 전체 사용자(사업자+소비자) 대상으로 강제 전환
function toggleUpdateAnnouncement() {
    const isUpdate = document.getElementById('pushIsUpdateAnnouncement')?.checked || false;
    const allRadio = document.querySelector('input[name="pushTarget"][value="all"]');
    const specificRadio = document.getElementById('pushTargetSpecificRadio');
    const targetAllLabelText = document.getElementById('pushTargetAllLabelText');

    if (isUpdate) {
        if (allRadio) allRadio.checked = true;
        if (specificRadio) specificRadio.disabled = true;
        if (targetAllLabelText) targetAllLabelText.textContent = '전체 사용자 (사업자+소비자)';
        togglePushTarget();

        // 제목/내용이 비어 있으면 업데이트 안내 기본 문구를 채워줌
        const titleEl = document.getElementById('pushTitle');
        const bodyEl = document.getElementById('pushBody');
        if (titleEl && !titleEl.value.trim()) {
            titleEl.value = '업데이트 안내';
            document.getElementById('pushTitleCount').textContent = titleEl.value.length + ' / 30';
        }
        if (bodyEl && !bodyEl.value.trim()) {
            bodyEl.value = '새 버전이 나왔어요! 지금 업데이트하세요';
            document.getElementById('pushBodyCount').textContent = bodyEl.value.length + ' / 30';
        }
    } else {
        if (specificRadio) specificRadio.disabled = false;
        if (targetAllLabelText) targetAllLabelText.textContent = '전체 사업자';
    }
}

let _pushBizTimer = null;
function searchPushBiz(q) {
    clearTimeout(_pushBizTimer);
    _pushBizTimer = setTimeout(async () => {
        if (!q.trim()) { document.getElementById('pushBizResults').innerHTML = ''; return; }
        try {
            const res = await apiCall(`/users/search?q=${encodeURIComponent(q)}`);
            const users = Array.isArray(res) ? res : [];
            const container = document.getElementById('pushBizResults');
            if (!container) return;
            if (!users.length) { container.innerHTML = '<div style="padding:0.7rem 1rem;color:var(--gray-400);font-size:0.875rem;">검색 결과 없음</div>'; return; }
            container.innerHTML = users.map(u => `
                <div style="padding:0.6rem 1rem;border-bottom:1px solid var(--gray-100);cursor:pointer;display:flex;align-items:center;justify-content:space-between;font-size:0.875rem;"
                    onclick="addPushBiz('${u.id}', '${(u.businessname || u.name || '').replace(/'/g,"\\'")}')">
                    <span>${u.businessname || u.name}</span>
                    <span class="material-icons" style="font-size:1rem;color:var(--primary);">add_circle_outline</span>
                </div>`).join('');
        } catch(e) { console.error(e); }
    }, 400);
}

function addPushBiz(id, name) {
    if (_selectedPushUserIds.includes(id)) return;
    _selectedPushUserIds.push(id);
    const list = document.getElementById('pushSelectedBizList');
    if (!list) return;
    const chip = document.createElement('div');
    chip.id = `push_chip_${id}`;
    chip.style.cssText = 'display:inline-flex;align-items:center;gap:0.35rem;background:#eff6ff;border:1px solid #bfdbfe;color:#1e3a8a;padding:0.3rem 0.7rem;border-radius:20px;font-size:0.8rem;cursor:pointer;';
    chip.innerHTML = `${name} <span onclick="removePushBiz('${id}')" style="font-size:0.95rem;color:#9ca3af;">&times;</span>`;
    list.appendChild(chip);
    document.getElementById('pushBizResults').innerHTML = '';
    document.getElementById('pushBizSearch').value = '';
}

function removePushBiz(id) {
    _selectedPushUserIds = _selectedPushUserIds.filter(x => x !== id);
    document.getElementById(`push_chip_${id}`)?.remove();
}

async function sendPushNotification() {
    const title = document.getElementById('pushTitle')?.value.trim();
    const body = document.getElementById('pushBody')?.value.trim();
    if (!title) { alert('제목을 입력해 주세요.'); return; }
    if (!body) { alert('내용을 입력해 주세요.'); return; }
    if (title.length > 30 || body.length > 30) { alert('텍스트는 30자 이하로 입력해 주세요.'); return; }

    const isUpdateAnnouncement = document.getElementById('pushIsUpdateAnnouncement')?.checked || false;
    const targetAll = isUpdateAnnouncement ? true : document.querySelector('input[name="pushTarget"]:checked')?.value === 'all';
    if (!targetAll && _selectedPushUserIds.length === 0) { alert('발송 대상 사업자를 선택해 주세요.'); return; }

    const confirmMsg = isUpdateAnnouncement
        ? '전체 사용자(사업자+소비자)에게 앱 업데이트 알림을 보내시겠습니까?\n탭하면 스토어로 이동합니다.'
        : `${targetAll ? '전체 사업자' : `${_selectedPushUserIds.length}명`}에게 푸시 알림을 보내시겠습니까?`;
    if (!confirm(confirmMsg)) return;

    const resultEl = document.getElementById('pushResult');
    if (resultEl) { resultEl.style.display = 'block'; resultEl.style.background = '#f0f7ff'; resultEl.style.color = '#1e3a8a'; resultEl.innerHTML = '⏳ 발송 중...'; }

    try {
        const result = await apiCall('/push-notifications/send', {
            method: 'POST',
            body: JSON.stringify({
                title, body, targetAll,
                userIds: _selectedPushUserIds,
                notificationType: isUpdateAnnouncement ? 'app_update' : undefined,
                allUserRoles: isUpdateAnnouncement,
            }),
        });
        if (resultEl) {
            resultEl.style.background = '#dcfce7'; resultEl.style.color = '#166534';
            resultEl.innerHTML = `✅ 발송 완료! 총 ${result.total || 0}명 중 ${result.sent || 0}명 성공`;
        }
        document.getElementById('pushTitle').value = '';
        document.getElementById('pushBody').value = '';
        document.getElementById('pushTitleCount').textContent = '0 / 30';
        document.getElementById('pushBodyCount').textContent = '0 / 30';
        _selectedPushUserIds = [];
        document.getElementById('pushSelectedBizList').innerHTML = '';
        document.getElementById('pushIsUpdateAnnouncement').checked = false;
        toggleUpdateAnnouncement();
    } catch(e) {
        if (resultEl) { resultEl.style.background = '#fee2e2'; resultEl.style.color = '#991b1b'; resultEl.innerHTML = `❌ 발송 실패: ${e.message}`; }
    }
}

// ══════════════════════════════════════════════════════════════
// 추천 업체 관리 (이번 달 우수 업체)
// ══════════════════════════════════════════════════════════════

async function loadFeaturedBusinesses() {
    const container = document.getElementById('featuredBizList');
    if (container) container.innerHTML = '<div class="loading"><div class="spinner"></div>로딩 중...</div>';
    try {
        const data = await apiCall('/featured-businesses');
        renderFeaturedBusinesses(Array.isArray(data) ? data : []);
    } catch(e) {
        console.error('[loadFeaturedBusinesses]', e);
        if (container) {
            // 테이블 미생성 안내
            const isMissing = e.message && (e.message.includes('42P01') || e.message.includes('does not exist'));
            container.innerHTML = isMissing
                ? `<div style="padding:1rem;background:#fffbeb;border:1px solid #fcd34d;border-radius:8px;font-size:0.85rem;color:#92400e;">
                     ⚠️ <strong>web_featured_businesses</strong> 테이블이 없습니다.<br>
                     Supabase SQL Editor에서 <code>database/web_featured_push.sql</code>을 실행해 주세요.
                   </div>`
                : `<div style="padding:1rem;color:#991b1b;font-size:0.875rem;">❌ 로드 실패: ${e.message}</div>`;
        }
    }
}

function renderFeaturedBusinesses(list) {
    const container = document.getElementById('featuredBizList');
    if (!container) return;
    if (!list || !list.length) {
        container.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--gray-400);">아직 등록된 추천 업체가 없습니다.<br><small>위 검색창에서 사업자를 찾아 추가해 주세요.</small></div>';
        return;
    }
    container.innerHTML = `
        <div style="display:flex;flex-direction:column;gap:0.5rem;">
            ${list.map((item, idx) => {
                const u = item.users || {};
                const name = u.businessname || u.name || `(ID: ${item.user_id?.slice(0,8)}...)`;
                const category = u.category || '';
                const region = u.region || '';
                const phone = u.phonenumber || '';
                return `<div style="display:flex;align-items:center;gap:0.75rem;padding:0.9rem 1rem;background:#f9fafb;border:1px solid var(--gray-200);border-radius:10px;">
                    <span style="background:#1e3a8a;color:#fff;width:24px;height:24px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:0.75rem;font-weight:700;flex-shrink:0;">${idx+1}</span>
                    <div style="flex:1;min-width:0;">
                        <div style="font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${name}</div>
                        <div style="font-size:0.78rem;color:var(--gray-500);">${[category, region, phone].filter(Boolean).join(' · ')}</div>
                    </div>
                    <button class="btn btn-sm" style="background:#fee2e2;color:#991b1b;border-color:#fca5a5;flex-shrink:0;" onclick="removeFeaturedBiz('${item.id}')">삭제</button>
                </div>`;
            }).join('')}
        </div>`;
}

let _featBizTimer = null;
function searchFeaturedBiz(q) {
    clearTimeout(_featBizTimer);
    _featBizTimer = setTimeout(async () => {
        const container = document.getElementById('featuredBizSearchResults');
        if (!container) return;
        if (!q.trim()) { container.innerHTML = ''; return; }
        try {
            const res = await apiCall(`/users/search?q=${encodeURIComponent(q)}`);
            const users = Array.isArray(res) ? res : [];
            if (!users.length) { container.innerHTML = '<div style="padding:0.5rem;color:var(--gray-400);font-size:0.875rem;">검색 결과 없음</div>'; return; }
            container.innerHTML = `<div style="border:1px solid var(--gray-200);border-radius:10px;overflow:hidden;">
                ${users.map(u => `
                    <div style="padding:0.6rem 1rem;border-bottom:1px solid var(--gray-100);display:flex;align-items:center;justify-content:space-between;font-size:0.875rem;">
                        <span>${u.businessname || u.name}</span>
                        <button class="btn btn-primary btn-sm" onclick="addFeaturedBiz('${u.id}')">추가</button>
                    </div>`).join('')}
            </div>`;
        } catch(e) { console.error(e); }
    }, 400);
}

async function addFeaturedBiz(userId) {
    try {
        await apiCall('/featured-businesses', { method: 'POST', body: JSON.stringify({ userId, sortOrder: 0 }) });
        showToast('✅ 추천 업체에 추가되었습니다.');
        document.getElementById('featuredBizSearch').value = '';
        document.getElementById('featuredBizSearchResults').innerHTML = '';
        await loadFeaturedBusinesses();
    } catch(e) { alert('추가 실패: ' + e.message); }
}

async function removeFeaturedBiz(id) {
    if (!confirm('추천 업체에서 제거하시겠습니까?')) return;
    await apiCall(`/featured-businesses/${id}`, { method: 'DELETE' });
    showToast('🗑️ 제거되었습니다.');
    await loadFeaturedBusinesses();
}

// 페이지 로드 시 초기화
document.addEventListener('DOMContentLoaded', () => {
    console.log('🚀 Admin page initializing...');
    checkLogin();
    loadAll();
});
