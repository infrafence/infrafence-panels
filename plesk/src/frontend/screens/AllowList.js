// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useState,
    Button,
    FormFieldText,
    Label,
    List,
    ListAction,
    ListActions,
    ListEmptyView,
    Paragraph,
    Toolbar,
    ToolbarGroup,
} from '@plesk/ui-library';
import { post } from '../api';
import { code, errorText, sentences, t } from '../i18n';
import { ConfirmDialog, ErrorAlert, ListLoading, Mono, RefreshButton, Time, toast, useAgent } from '../common';

const IPV4 = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;
const IPV6 = /^[0-9a-f:.]{2,45}$/i;

// Quick check while typing; the server and the agent validate strictly. One address, no range.
const looksValid = value => {
    const ip = value.trim();
    return IPV4.test(ip) || (IPV6.test(ip) && ip.includes(':'));
};

const NOTE_MAX_BYTES = 200;
const noteBytes = value => new TextEncoder().encode(value).length;

const FIELD_ERRORS = ['invalid_ip', 'loopback_address', 'invalid_note', 'bad_request'];

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
            const address = reply.ip || ip.trim();
            if (reply.own_address) {
                toast('warning', t('allowlist.ownAddress', { ip: address }));
            } else if (reply.already) {
                toast('info', t('allowlist.already', { ip: address }));
            } else {
                toast(reply.banned ? 'warning' : 'success', sentences(
                    t('allowlist.added', { ip: address }),
                    reply.banned ? t('allowlist.alsoBanned') : '',
                    reply.reported === false ? t('result.notReported') : '',
                ));
            }
            setAdding(false);
            list.reload();
        } else if (FIELD_ERRORS.includes(reply.error)) {
            setFieldError(errorText(reply.error));
        } else {
            toast('danger', errorText(reply.error));
        }
    });

    const remove = () => post('disallow', { ip: removing.address }).then(reply => {
        if (reply.ok) {
            toast('success', sentences(
                t('allowlist.removed', { ip: reply.ip || removing.address }),
                reply.reported === false ? t('result.notReported') : '',
            ));
        } else {
            toast('danger', errorText(reply.error));
        }
        if (reply.ok || reply.error === 'not_in_allowlist' || reply.error === 'managed_by_dashboard') {
            setRemoving(null);
            list.reload();
        }
    });

    const columns = [
        { key: 'address', title: t('allowlist.col.address'), type: 'title', render: row => <Mono>{row.address}</Mono> },
        {
            key: 'source',
            title: t('allowlist.col.source'),
            render: row => <Label intent={row.source === 'panel' ? 'info' : 'inactive'} view="light">{code('allowSource', row.source)}</Label>,
        },
        { key: 'note', title: t('allowlist.col.note'), render: row => row.note || <span className="infrafence__muted">–</span> },
        { key: 'actor', title: t('allowlist.col.actor'), render: row => row.actor || <span className="infrafence__muted">–</span> },
        { key: 'added', title: t('allowlist.col.added'), render: row => <Time value={row.added} empty="–" /> },
        {
            key: 'actions',
            type: 'actions',
            render: row => (row.source === 'panel' ? (
                <ListActions>
                    <ListAction primary icon="remove" onClick={() => setRemoving(row)}>{t('allowlist.remove')}</ListAction>
                </ListActions>
            ) : (
                <span className="infrafence__muted" title={t('allowlist.dashboardEntry')}>{t('allowlist.inDashboard')}</span>
            )),
        },
    ];

    const valid = looksValid(ip) && noteBytes(note) <= NOTE_MAX_BYTES;

    return (
        <div>
            {list.error ? <ErrorAlert error={list.error} onRetry={list.reload} status={status} /> : null}
            <Paragraph className="infrafence__intro">{t('allowlist.intro')}</Paragraph>
            {list.error && !list.data ? null : (
                <List
                    columns={columns}
                    data={list.data ? list.data.allowlist : []}
                    rowKey="address"
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
                    inputProps={{ autoFocus: true, maxLength: 45, autoComplete: 'off' }}
                    required
                    size="fill"
                />
                <FormFieldText
                    name="note"
                    label={t('allowlist.note')}
                    value={note}
                    onChange={setNote}
                    errors={noteBytes(note) > NOTE_MAX_BYTES ? [t('errors.invalid_note')] : undefined}
                    inputProps={{ maxLength: 200 }}
                    size="fill"
                />
            </ConfirmDialog>
            <ConfirmDialog
                isOpen={!!removing}
                title={removing ? t('allowlist.removeTitle', { ip: removing.address }) : ''}
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
