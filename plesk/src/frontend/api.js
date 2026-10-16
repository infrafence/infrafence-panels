// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

let apiUrl = '';

export const setApiUrl = url => {
    apiUrl = url;
};

const token = () => {
    const meta = document.getElementById('forgery_protection_token') || document.querySelector('meta[name="forgery_protection_token"]');
    return meta ? meta.content : '';
};

// The API answers 400/401 without a valid session and 403 for a missing or wrong forgery
// protection token (or a non-administrator), with no JSON body.
const statusError = (status, method) => {
    if (status === 400 || status === 401) {
        return 'csrf_token_missing';
    }
    if (status === 403) {
        return method === 'POST' ? 'csrf_token_missing' : 'access_denied';
    }
    return 'bad_reply';
};

const request = async (action, params, options) => {
    const query = new URLSearchParams({ action, ...params }).toString();
    try {
        const response = await fetch(`${apiUrl}?${query}`, {
            credentials: 'same-origin',
            ...options,
            headers: {
                'X-Requested-With': 'XMLHttpRequest',
                Accept: 'application/json',
                ...options.headers,
            },
        });
        const data = await response.json().catch(() => null);
        if (!data || typeof data.ok !== 'boolean') {
            return { ok: false, error: statusError(response.status, options.method) };
        }
        return data;
    } catch (e) {
        return { ok: false, error: 'network' };
    }
};

export const get = (action, params = {}) => request(action, params, { method: 'GET' });

export const post = (action, body = {}) => request(action, {}, {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'X-Forgery-Protection-Token': token(),
    },
    body: JSON.stringify(body),
});
