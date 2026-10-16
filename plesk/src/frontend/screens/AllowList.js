// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useState,
    Button,
    FormFieldText,
    List,
    ListAction,
    ListActions,
    ListEmptyView,
    Paragraph,
    Toolbar,
    ToolbarGroup,
} from '@plesk/ui-library';
import { post } from '../api';
import { errorText, t } from '../i18n';
import { ConfirmDialog, ErrorAlert, ListLoading, Mono, RefreshButton, runAction, Time, useAgent } from '../common';

const IPV4 = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;
const IPV6 = /^[0-9a-f:.]{2,45}$/i;

// Quick check while typing; the server validates strictly.
const looksValid = value => {
    const [ip, prefix, extra] = value.trim().split('/');
    if (extra !== undefined || !ip) {
        return false;
    }
    const v4 = IPV4.test(ip);
    const v6 = !v4 && IPV6.test(ip) && ip.includes(':');
    if (!v4 && !v6) {
        return false;
    }
    if (prefix === undefined) {
        return true;
    }
    const n = Number(prefix);
    return /^\d{1,3}$/.test(prefix) && n >= (v4 ? 16 : 48) && n <= (v4 ? 32 : 128);
};

const AllowList = ({ status }) => {
    const list = useAgent('allowlist');
    const [adding, setAdding] = useState(false);
    const [ip, setIp] = useState('');
    const [note, setNote] = useState('');
    const [fieldError, setFieldError] = useState(null);
    const [removing, setRemoving] = useState(null);

    const openAdd = () => {
        setIp('');
        setNote('');
        setFieldError(null);
        setAdding(true);
    };

    const add = () => post('allow', { ip: ip.trim(), note }).then(reply => {
        if (reply.ok) {
            runAction(Promise.resolve(reply), t('allowlist.added', { ip: reply.ip || ip.trim() }));
            setAdding(false);
            list.reload();
        } else if (['invalid_ip', 'unusable_ip', 'network_too_wide', 'already_allowed', 'invalid_note'].includes(reply.error)) {
            setFieldError(reply.error === 'already_allowed' ? t('errors.already_allowed', { entry: reply.entry || '' }) : errorText(reply.error));
        } else {
            runAction(Promise.resolve(reply));
        }
    });

    const remove = () => runAction(post('disallow', { ip: removing.ip }), t('allowlist.removed', { ip: removing.ip })).then(reply => {
        if (reply.ok || reply.error === 'not_allowed') {
            setRemoving(null);
            list.reload();
        }
    });

    const columns = [
        { key: 'ip', title: t('allowlist.col.ip'), type: 'title', sortable: true, render: row => <Mono>{row.ip}</Mono> },
        { key: 'note', title: t('allowlist.col.note'), render: row => row.note || <span className="infrafence__muted">–</span> },
        { key: 'actor', title: t('allowlist.col.actor'), render: row => row.actor || '–' },
        { key: 'created', title: t('allowlist.col.created'), sortable: true, render: row => <Time value={row.created} /> },
        {
            key: 'actions',
            type: 'actions',
            render: row => (
                <ListActions>
                    <ListAction primary icon="remove" onClick={() => setRemoving(row)}>{t('allowlist.remove')}</ListAction>
                </ListActions>
            ),
        },
    ];

    const valid = looksValid(ip);

    return (
        <div>
            {list.error ? <ErrorAlert error={list.error} onRetry={list.reload} status={status} /> : null}
            <Paragraph className="infrafence__intro">{t('allowlist.intro')}</Paragraph>
            {list.error && !list.data ? null : (
                <List
                    columns={columns}
                    data={list.data ? list.data.entries : []}
                    rowKey="ip"
                    toolbar={(
                        <Toolbar>
                            <ToolbarGroup title={t('allowlist.add')}>
                                <Button intent="primary" icon="plus" onClick={openAdd}>{t('allowlist.add')}</Button>
                            </ToolbarGroup>
                            <ToolbarGroup title={t('common.refresh')}>
                                <RefreshButton loading={list.loading} onClick={list.reload} />
                            </ToolbarGroup>
                        </Toolbar>
                    )}
                    emptyView={list.loading && !list.data ? <ListLoading /> : (
                        <ListEmptyView
                            title={t('allowlist.empty')}
                            description={t('allowlist.emptyHint')}
                            actions={<Button icon="plus" onClick={openAdd}>{t('allowlist.add')}</Button>}
                        />
                    )}
                />
            )}
            <ConfirmDialog
                isOpen={adding}
                title={t('allowlist.addTitle')}
                confirmText={t('allowlist.addConfirm')}
                canConfirm={valid}
                onConfirm={add}
                onClose={() => setAdding(false)}
            >
                <Paragraph>{t('allowlist.addText')}</Paragraph>
                <FormFieldText
                    name="ip"
                    label={t('allowlist.ip')}
                    description={t('allowlist.ipHint')}
                    value={ip}
                    onChange={value => { setIp(value); setFieldError(null); }}
                    errors={fieldError ? [fieldError] : undefined}
                    inputProps={{ autoFocus: true, maxLength: 49, autoComplete: 'off' }}
                    required
                    size="fill"
                />
                <FormFieldText
                    name="note"
                    label={t('allowlist.note')}
                    value={note}
                    onChange={setNote}
                    inputProps={{ maxLength: 200 }}
                    size="fill"
                />
            </ConfirmDialog>
            <ConfirmDialog
                isOpen={!!removing}
                title={removing ? t('allowlist.removeTitle', { ip: removing.ip }) : ''}
                confirmText={t('allowlist.remove')}
                intent="danger"
                onConfirm={remove}
                onClose={() => setRemoving(null)}
            >
                {t('allowlist.removeText')}
            </ConfirmDialog>
        </div>
    );
};

export default AllowList;
