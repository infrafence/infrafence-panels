// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import { locale, t } from './i18n';

const parse = value => {
    if (!value) {
        return null;
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
};

export const dateTime = value => {
    const date = parse(value);
    if (!date) {
        return '';
    }
    try {
        return new Intl.DateTimeFormat(locale(), { dateStyle: 'medium', timeStyle: 'short' }).format(date);
    } catch (e) {
        return date.toLocaleString();
    }
};

const UNITS = [
    ['year', 31536000],
    ['month', 2592000],
    ['day', 86400],
    ['hour', 3600],
    ['minute', 60],
];

export const relative = value => {
    const date = parse(value);
    if (!date) {
        return '';
    }
    const seconds = Math.round((date.getTime() - Date.now()) / 1000);
    if (Math.abs(seconds) < 45) {
        return t('time.justNow');
    }
    let rtf;
    try {
        rtf = new Intl.RelativeTimeFormat(locale(), { numeric: 'auto' });
    } catch (e) {
        return dateTime(value);
    }
    for (const [unit, size] of UNITS) {
        if (Math.abs(seconds) >= size || unit === 'minute') {
            return rtf.format(Math.round(seconds / size), unit);
        }
    }
    return dateTime(value);
};

export const number = value => {
    if (value === null || value === undefined) {
        return '';
    }
    try {
        return new Intl.NumberFormat(locale()).format(value);
    } catch (e) {
        return String(value);
    }
};

export const ageSeconds = value => {
    const date = parse(value);
    return date ? (Date.now() - date.getTime()) / 1000 : Infinity;
};
