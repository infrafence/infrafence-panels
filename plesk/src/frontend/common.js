// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useCallback,
    useEffect,
    useRef,
    useState,
    Alert,
    Button,
    Dialog,
    Paragraph,
    SkeletonText,
    Toaster,
} from '@plesk/ui-library';
import { get } from './api';
import { errorText, t } from './i18n';
import { dateTime, relative } from './format';

let toaster = null;

/**
 * Mounted once by App; toast() then reports action results in Plesk's own toaster style.
 */
export const ToastHost = () => <Toaster ref={instance => { toaster = instance; }} />;

export const toast = (intent, message) => {
    if (toaster && message) {
        toaster.add({ intent, message, autoClosable: intent !== 'danger' });
    }
};

/**
 * Loads one read endpoint and keeps the last good reply while reloading.
 */
export const useAgent = (action, params = {}) => {
    const key = JSON.stringify(params);
    const [state, setState] = useState({ loading: true, data: null, error: null });
    const seq = useRef(0);

    const reload = useCallback(() => {
        const id = ++seq.current;
        setState(s => ({ ...s, loading: true }));
        return get(action, JSON.parse(key)).then(reply => {
            if (id !== seq.current) {
                return reply;
            }
            setState(s => (reply.ok
                ? { loading: false, data: reply, error: null }
                : { loading: false, data: s.data, error: reply.error }));
            return reply;
        });
    }, [action, key]);

    useEffect(() => {
        reload();
    }, [reload]);

    return { ...state, reload };
};

export const Time = ({ value, empty = '' }) => {
    if (!value) {
        return <span className="infrafence__muted">{empty}</span>;
    }
    return <span title={dateTime(value)}>{relative(value)}</span>;
};

export const Mono = ({ children }) => <span className="infrafence__mono">{children}</span>;

/**
 * Error of one screen. When the agent is stopped, App already says so above the tabs.
 */
export const ErrorAlert = ({ error, onRetry, status }) => (status && !status.agent_running && error === 'agent_not_running' ? null : (
    <Alert intent={error === 'agent_not_running' ? 'warning' : 'danger'}>
        {errorText(error)}
        {onRetry ? (
            <span className="infrafence__alert-action">
                <Button ghost onClick={onRetry} icon="refresh">{t('common.retry')}</Button>
            </span>
        ) : null}
    </Alert>
));

export const RefreshButton = ({ loading, onClick }) => (
    <Button icon="refresh" ghost state={loading ? 'loading' : undefined} onClick={onClick} tooltip={t('common.refresh')}>
        {t('common.refresh')}
    </Button>
);

/**
 * Confirmation for every action that changes something. `onConfirm` returns a promise;
 * the dialog stays open with the button in its loading state until it settles.
 */
export const ConfirmDialog = ({ isOpen, title, children, confirmText, intent = 'primary', onConfirm, onClose, canConfirm = true }) => {
    const [busy, setBusy] = useState(false);

    useEffect(() => {
        if (!isOpen) {
            setBusy(false);
        }
    }, [isOpen]);

    const confirm = () => {
        if (busy) {
            return;
        }
        setBusy(true);
        Promise.resolve(onConfirm()).finally(() => setBusy(false));
    };

    return (
        <Dialog
            isOpen={isOpen}
            title={title}
            size="sm"
            onClose={busy ? undefined : onClose}
            canClose={!busy}
            cancelButton={{ children: t('common.cancel'), disabled: busy }}
            buttons={(
                <Button intent={intent} state={busy ? 'loading' : undefined} disabled={!canConfirm} onClick={confirm}>
                    {confirmText}
                </Button>
            )}
        >
            {typeof children === 'string' ? <Paragraph>{children}</Paragraph> : children}
        </Dialog>
    );
};

/**
 * Runs an action and reports the outcome in a toast. Resolves to the agent reply.
 */
export const runAction = (promise, successMessage) => promise.then(reply => {
    if (reply.ok) {
        toast('success', successMessage);
    } else {
        toast('danger', errorText(reply.error));
    }
    return reply;
});

export const ListLoading = () => (
    <div className="infrafence__list-loading">
        <SkeletonText lines={4} />
    </div>
);
