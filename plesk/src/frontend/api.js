// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

let apiUrl = '';

export const setApiUrl = url => {
    apiUrl = url.replace(/\/+$/, '');
};

const token = () => {
    const meta = document.getElementById('forgery_protection_token') || document.querySelector('meta[name="forgery_protection_token"]');
    return meta ? meta.content : '';
};

const request = async (action, options) => {
    try {
        const response = await fetch(`${apiUrl}/${action}`, {
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
            return { ok: false, error: response.status === 403 ? 'access_denied' : 'bad_reply' };
        }
        return data;
    } catch (e) {
        return { ok: false, error: 'network' };
    }
};

export const get = (action, params = {}) => {
    const query = new URLSearchParams(params).toString();
    return request(query ? `${action}?${query}` : action, { method: 'GET' });
};

export const post = (action, body = {}) => request(action, {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'X-Forgery-Protection-Token': token(),
    },
    body: JSON.stringify(body),
});
