// API Configuration
const API_BASE_URL = '/api';
const FEEDBACKS_ENDPOINT = `${API_BASE_URL}/feedbacks`;

// State
let currentPage = 0;
let currentSize = 10;
let currentFilter = null;

// DOM Elements
const feedbackForm = document.getElementById('feedbackForm');
const usernameInput = document.getElementById('username');
const messageInput = document.getElementById('message');
const charCount = document.getElementById('charCount');
const feedbackList = document.getElementById('feedbackList');
const loading = document.getElementById('loading');
const error = document.getElementById('error');
const errorMessage = document.getElementById('errorMessage');
const emptyState = document.getElementById('emptyState');
const pagination = document.getElementById('pagination');
const totalCount = document.getElementById('totalCount');
const toast = document.getElementById('toast');
const toastMessage = document.getElementById('toastMessage');
const filterBtn = document.getElementById('filterBtn');
const clearFilterBtn = document.getElementById('clearFilterBtn');
const filterUsername = document.getElementById('filterUsername');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    loadFeedbacks();
    setupEventListeners();
});

// Event Listeners
function setupEventListeners() {
    // Form submission
    feedbackForm.addEventListener('submit', handleSubmit);

    // Character count
    messageInput.addEventListener('input', updateCharCount);

    // Filter
    filterBtn.addEventListener('click', applyFilter);
    clearFilterBtn.addEventListener('click', clearFilter);
    filterUsername.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            applyFilter();
        }
    });
}

// Character count update
function updateCharCount() {
    const length = messageInput.value.length;
    charCount.textContent = length;
}

// Apply filter
function applyFilter() {
    const username = filterUsername.value.trim();
    if (username) {
        currentFilter = username;
        currentPage = 0;
        loadFeedbacks();
    }
}

// Clear filter
function clearFilter() {
    currentFilter = null;
    filterUsername.value = '';
    currentPage = 0;
    loadFeedbacks();
}

// Handle form submission
async function handleSubmit(e) {
    e.preventDefault();

    const username = usernameInput.value.trim() || null;
    const message = messageInput.value.trim();

    if (!message) {
        showToast('메시지를 입력해주세요', 'error');
        return;
    }

    try {
        const response = await fetch(FEEDBACKS_ENDPOINT, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ username, message }),
        });

        const result = await response.json();

        if (response.ok && result.success) {
            showToast('피드백이 등록되었습니다!', 'success');
            feedbackForm.reset();
            updateCharCount();
            currentPage = 0;
            loadFeedbacks();
        } else {
            throw new Error(result.message || '피드백 등록에 실패했습니다');
        }
    } catch (err) {
        console.error('Error submitting feedback:', err);
        showToast(err.message || '피드백 등록에 실패했습니다', 'error');
    }
}

// Load feedbacks
async function loadFeedbacks() {
    showLoading(true);
    hideError();

    try {
        let url = `${FEEDBACKS_ENDPOINT}?page=${currentPage}&size=${currentSize}`;

        if (currentFilter) {
            url += `&username=${encodeURIComponent(currentFilter)}`;
        }

        const response = await fetch(url);
        const result = await response.json();

        if (response.ok && result.success) {
            renderFeedbacks(result.data);
        } else {
            throw new Error(result.message || '피드백을 불러오는데 실패했습니다');
        }
    } catch (err) {
        console.error('Error loading feedbacks:', err);
        showError(err.message);
    } finally {
        showLoading(false);
    }
}

// Render feedbacks
function renderFeedbacks(data) {
    const { content, totalElements, totalPages, currentPage: page } = data;

    // Update total count
    totalCount.textContent = totalElements;

    // Clear list
    feedbackList.innerHTML = '';

    // Show empty state if no feedbacks
    if (content.length === 0) {
        emptyState.classList.remove('hidden');
        pagination.innerHTML = '';
        return;
    }

    emptyState.classList.add('hidden');

    // Render feedback items
    content.forEach(feedback => {
        const item = createFeedbackItem(feedback);
        feedbackList.appendChild(item);
    });

    // Render pagination
    renderPagination(totalPages, page);
}

// Create feedback item
function createFeedbackItem(feedback) {
    const div = document.createElement('div');
    div.className = 'feedback-item border border-gray-200 rounded-lg p-4 hover:shadow-md transition duration-200';

    const createdAt = new Date(feedback.createdAt);
    const formattedDate = formatDate(createdAt);

    div.innerHTML = `
        <div class="flex justify-between items-start mb-2">
            <div class="flex items-center gap-2">
                <div class="w-10 h-10 rounded-full bg-indigo-100 flex items-center justify-center">
                    <span class="text-indigo-600 font-semibold text-lg">
                        ${feedback.username.charAt(0).toUpperCase()}
                    </span>
                </div>
                <div>
                    <p class="font-semibold text-gray-800">${escapeHtml(feedback.username)}</p>
                    <p class="text-xs text-gray-500">${formattedDate}</p>
                </div>
            </div>
            <span class="text-xs text-gray-400">#${feedback.id}</span>
        </div>
        <div class="ml-12">
            <p class="text-gray-700 whitespace-pre-wrap break-words">${escapeHtml(feedback.message)}</p>
        </div>
    `;

    return div;
}

// Render pagination
function renderPagination(totalPages, currentPageNum) {
    pagination.innerHTML = '';

    if (totalPages <= 1) return;

    // Previous button
    const prevBtn = createPaginationButton('이전', currentPageNum > 0, () => {
        currentPage = currentPageNum - 1;
        loadFeedbacks();
    });
    pagination.appendChild(prevBtn);

    // Page numbers
    const startPage = Math.max(0, currentPageNum - 2);
    const endPage = Math.min(totalPages - 1, currentPageNum + 2);

    for (let i = startPage; i <= endPage; i++) {
        const pageBtn = createPageButton(i + 1, i === currentPageNum, () => {
            currentPage = i;
            loadFeedbacks();
        });
        pagination.appendChild(pageBtn);
    }

    // Next button
    const nextBtn = createPaginationButton('다음', currentPageNum < totalPages - 1, () => {
        currentPage = currentPageNum + 1;
        loadFeedbacks();
    });
    pagination.appendChild(nextBtn);
}

// Create pagination button
function createPaginationButton(text, enabled, onClick) {
    const button = document.createElement('button');
    button.textContent = text;
    button.className = `px-4 py-2 rounded-lg ${
        enabled
            ? 'bg-white text-gray-700 hover:bg-gray-100 border border-gray-300'
            : 'bg-gray-200 text-gray-400 cursor-not-allowed'
    }`;
    button.disabled = !enabled;
    if (enabled) {
        button.addEventListener('click', onClick);
    }
    return button;
}

// Create page button
function createPageButton(pageNum, isActive, onClick) {
    const button = document.createElement('button');
    button.textContent = pageNum;
    button.className = `pagination-btn px-4 py-2 rounded-lg border border-gray-300 ${
        isActive
            ? 'active'
            : 'bg-white text-gray-700 hover:bg-gray-100'
    }`;
    if (!isActive) {
        button.addEventListener('click', onClick);
    }
    return button;
}

// Show loading
function showLoading(show) {
    if (show) {
        loading.classList.remove('hidden');
        feedbackList.classList.add('hidden');
        emptyState.classList.add('hidden');
    } else {
        loading.classList.add('hidden');
        feedbackList.classList.remove('hidden');
    }
}

// Show error
function showError(message) {
    error.classList.remove('hidden');
    errorMessage.textContent = message;
}

// Hide error
function hideError() {
    error.classList.add('hidden');
    errorMessage.textContent = '';
}

// Show toast
function showToast(message, type = 'success') {
    toastMessage.textContent = message;

    if (type === 'error') {
        toast.classList.remove('bg-green-500');
        toast.classList.add('bg-red-500');
    } else {
        toast.classList.remove('bg-red-500');
        toast.classList.add('bg-green-500');
    }

    toast.classList.remove('hidden');
    toast.classList.add('show');

    setTimeout(() => {
        toast.classList.remove('show');
        toast.classList.add('hide');
        setTimeout(() => {
            toast.classList.add('hidden');
            toast.classList.remove('hide');
        }, 300);
    }, 3000);
}

// Format date
function formatDate(date) {
    const now = new Date();
    const diff = now - date;
    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (seconds < 60) return '방금 전';
    if (minutes < 60) return `${minutes}분 전`;
    if (hours < 24) return `${hours}시간 전`;
    if (days < 7) return `${days}일 전`;

    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hour = String(date.getHours()).padStart(2, '0');
    const minute = String(date.getMinutes()).padStart(2, '0');

    return `${year}-${month}-${day} ${hour}:${minute}`;
}

// Escape HTML to prevent XSS (additional client-side protection)
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
