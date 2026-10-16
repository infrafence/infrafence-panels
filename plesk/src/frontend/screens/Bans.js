// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useMemo,
    useState,
    Alert,
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
import { code, errorText, sentences, t } from '../i18n';
import { dateTime } from '../format';
import { ConfirmDialog, ErrorAlert, ListLoading, Mono, RefreshButton, Time, toast, useAgent } from '../common';

const SOURCE_INTENT = { local: 'info', network: 'warning', automode: 'success', manual: 'inactive' };

const matches = (ban, query) => {
    if (!query) {
        return true;
    }
    const q = query.toLowerCase();
    return [ban.ip, ban.reason, code('source', ban.source)].some(v => String(v || '').toLowerCase().includes(q));
};

const LIFT_MAX_DAYS = 30;

/**
 * When a lift ends at the latest, as the agent computes it: the ban's expiry, and never more
 * than 30 days from now. Shown before confirming; the reply then gives the exact `lifted_until`.
 */
const expectedLiftEnd = ban => {
    const max = Date.now() + LIFT_MAX_DAYS * 86400000;
    const expires = ban.expires ? new Date(ban.expires).getTime() : NaN;
    return new Date(Number.isNaN(expires) ? max : Math.min(expires, max)).toISOString();
};

/**
 * The lift is local to this server. Network and AutoMode bans stay on the organization's other
 * servers; dashboard bans stay in the dashboard.
 */
const sourceNote = source => {
    if (source === 'network' || source === 'automode') {
        return t('bans.keptElsewhere');
    }
    return source === 'manual' ? t('bans.keptInDashboard') : '';
};

/**
 * What the unban reply adds to the success message: lifted on this server only and until when,
 * where the ban stays, not reported yet, still on a threat list, firewall entry still pending.
 */
export const unbanNotes = reply => [
    reply.lifted_until ? t('bans.liftedUntil', { date: dateTime(reply.lifted_until) }) : '',
    sourceNote(reply.source),
    reply.reported === false ? t('result.notReported') : '',
    reply.threat_feed ? t('bans.threatFeed') : '',
    reply.firewall_pending ? t('bans.firewallPending') : '',
];

const Bans = ({ status }) => {
    const bans = useAgent('bans', { limit: 500 });
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
        if (!reply.ok) {
            toast('danger', errorText(reply.error));
        } else {
            const ip = reply.ip || pending.ip;
            const allow = reply.allow;
            let first = t('bans.unbanned', { ip });
            let intent = reply.threat_feed ? 'warning' : 'success';
            if (allow && allow.ok && !allow.already) {
                first = t('bans.unbannedAndAllowed', { ip });
            } else if (allow && allow.ok && allow.already) {
                first = sentences(first, t('allowlist.already', { ip }));
            } else if (allow) {
                first = sentences(first, t('bans.notAllowed'), errorText(allow.error));
                intent = 'warning';
            }
            toast(intent, sentences(first, ...unbanNotes(reply)));
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
            render: row => <Mono>{row.ip}</Mono>,
        },
        { key: 'reason', title: t('bans.col.reason'), render: row => row.reason || <span className="infrafence__muted">–</span> },
        {
            key: 'source',
            title: t('bans.col.source'),
            render: row => <Label intent={SOURCE_INTENT[row.source] || 'inactive'} view="light">{code('source', row.source)}</Label>,
        },
        { key: 'created', title: t('bans.col.created'), render: row => <Time value={row.created} empty="–" /> },
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
            {bans.data && bans.data.monitor_mode && !status.monitor_mode ? <Alert intent="info">{t('bans.monitorMode')}</Alert> : null}
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
            {bans.data && bans.data.total > bans.data.bans.length ? (
                <Paragraph className="infrafence__muted">{t('bans.more', { shown: bans.data.bans.length, total: bans.data.total })}</Paragraph>
            ) : null}
            <ConfirmDialog
                isOpen={!!pending}
                title={pending ? t(alsoAllow ? 'bans.confirmAllowTitle' : 'bans.confirmTitle', { ip: pending.ip }) : ''}
                confirmText={alsoAllow ? t('bans.unbanAndAllow') : t('bans.unban')}
                onConfirm={confirm}
                onClose={() => setPending(null)}
            >
                {pending ? (
                    <Paragraph>
                        {sentences(
                            t('bans.confirmLift', { date: dateTime(expectedLiftEnd(pending)) }),
                            sourceNote(pending.source),
                            alsoAllow ? t('bans.confirmAllow') : t('bans.confirmAgain'),
                        )}
                    </Paragraph>
                ) : null}
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
