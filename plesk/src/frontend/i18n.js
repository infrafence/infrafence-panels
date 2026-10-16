// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

let messages = {};
let localeCode = 'en-US';

export const setMessages = (value, code) => {
    messages = value || {};
    localeCode = code || 'en-US';
};

export const locale = () => localeCode;

export const has = key => Object.prototype.hasOwnProperty.call(messages, key);

/**
 * Translates `key`, replacing %%name%% placeholders (the Plesk locale convention).
 */
export const t = (key, params = {}) => {
    const text = has(key) ? messages[key] : key;
    return text.replace(/%%(\w+)%%/g, (match, name) => (name in params ? String(params[name]) : match));
};

/**
 * Translates a code reported by the agent (`group.code`). Unknown codes are shown readably,
 * so a newer agent never breaks the screen.
 */
export const code = (group, value) => {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    const key = `${group}.${value}`;
    if (has(key)) {
        return t(key);
    }
    const text = String(value).replace(/[_-]+/g, ' ');
    return text.charAt(0).toUpperCase() + text.slice(1);
};

export const errorText = error => (has(`errors.${error}`) ? t(`errors.${error}`) : t('errors.generic', { code: error }));
