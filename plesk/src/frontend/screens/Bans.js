// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useMemo,
    useState,
    Checkbox,
    FormFieldText,
    Label,
    List,
    ListAction,
    ListActions,
    ListEmptyView,
    Paragraph,
    SearchBar,
    Toolbar,
    ToolbarGroup,
} from '@plesk/ui-library';
import { post } from '../api';
import { code, t } from '../i18n';
import { ConfirmDialog, ErrorAlert, ListLoading, Mono, RefreshButton, runAction, Time, toast, useAgent } from '../common';

const SOURCE_INTENT = { local: 'info', network: 'warning', automode: 'success', manual: 'inactive' };

const matches = (ban, query) => {
    if (!query) {
        return true;
    }
    const q = query.toLowerCase();
    return [ban.ip, code('reason', ban.reason), code('source', ban.source)].some(v => String(v || '').toLowerCase().includes(q));
};

const Bans = ({ status }) => {
    const bans = useAgent('bans', { limit: 1000 });
    const [query, setQuery] = useState('');
    const [pending, setPending] = useState(null);
    const [alsoAllow, setAlsoAllow] = useState(false);
    const [note, setNote] = useState('');

    const rows = useMemo(
        () => (bans.data ? bans.data.bans.filter(b => matches(b, query)) : []),
        [bans.data, query],
    );

    const ask = (ban, allow) => {
        setAlsoAllow(allow);
        setNote('');
        setPending(ban);
    };

    const confirm = () => post('unban', { ip: pending.ip, allow: alsoAllow, note }).then(reply => {
        if (reply.ok && alsoAllow && reply.allowed === false) {
            toast('warning', t('bans.unbannedNotAllowed', { ip: pending.ip }));
        } else {
            runAction(Promise.resolve(reply), alsoAllow
                ? t('bans.unbannedAndAllowed', { ip: pending.ip })
                : t('bans.unbanned', { ip: pending.ip }));
        }
        if (reply.ok || reply.error === 'not_banned') {
            setPending(null);
            bans.reload();
        }
    });

    const columns = [
        {
            key: 'ip',
            title: t('bans.col.ip'),
            type: 'title',
            sortable: true,
            render: row => <Mono>{row.ip}</Mono>,
        },
        { key: 'reason', title: t('bans.col.reason'), render: row => code('reason', row.reason) },
        {
            key: 'source',
            title: t('bans.col.source'),
            render: row => <Label intent={SOURCE_INTENT[row.source] || 'inactive'} view="light">{code('source', row.source)}</Label>,
        },
        { key: 'created', title: t('bans.col.created'), sortable: true, render: row => <Time value={row.created} /> },
        { key: 'expires', title: t('bans.col.expires'), render: row => <Time value={row.expires} empty={t('bans.permanent')} /> },
        {
            key: 'actions',
            type: 'actions',
            render: row => (
                <ListActions>
                    <ListAction primary icon="lock-open" onClick={() => ask(row, false)}>{t('bans.unban')}</ListAction>
                    <ListAction icon="check-mark-circle" onClick={() => ask(row, true)}>{t('bans.unbanAndAllow')}</ListAction>
                </ListActions>
            ),
        },
    ];

    return (
        <div>
            {bans.error ? <ErrorAlert error={bans.error} onRetry={bans.reload} status={status} /> : null}
            <Paragraph className="infrafence__intro">{t('bans.intro')}</Paragraph>
            {bans.error && !bans.data ? null : (
                <List
                    columns={columns}
                    data={rows}
                    rowKey="ip"
                    filtered={!!query}
                    toolbar={(
                        <Toolbar>
                            <ToolbarGroup title={t('common.search')}>
                                <SearchBar
                                    inputProps={{ placeholder: t('bans.search'), value: query }}
                                    onTyping={value => setQuery(value)}
                                />
                            </ToolbarGroup>
                            <ToolbarGroup title={t('common.refresh')}>
                                <RefreshButton loading={bans.loading} onClick={bans.reload} />
                            </ToolbarGroup>
                        </Toolbar>
                    )}
                    emptyView={bans.loading && !bans.data ? <ListLoading /> : (
                        <ListEmptyView
                            title={query ? t('common.noMatches') : t('bans.empty')}
                            description={query ? null : t('bans.emptyHint')}
                            reason={query ? 'filtered' : undefined}
                        />
                    )}
                />
            )}
            <ConfirmDialog
                isOpen={!!pending}
                title={pending ? t(alsoAllow ? 'bans.confirmAllowTitle' : 'bans.confirmTitle', { ip: pending.ip }) : ''}
                confirmText={alsoAllow ? t('bans.unbanAndAllow') : t('bans.unban')}
                onConfirm={confirm}
                onClose={() => setPending(null)}
            >
                <Paragraph>{alsoAllow ? t('bans.confirmAllowText') : t('bans.confirmText')}</Paragraph>
                <Checkbox checked={alsoAllow} onChange={setAlsoAllow}>{t('bans.alsoAllow')}</Checkbox>
                {alsoAllow ? (
                    <FormFieldText
                        name="note"
                        label={t('allowlist.note')}
                        value={note}
                        onChange={setNote}
                        inputProps={{ maxLength: 200 }}
                        size="fill"
                    />
                ) : null}
            </ConfirmDialog>
        </div>
    );
};

export default Bans;
