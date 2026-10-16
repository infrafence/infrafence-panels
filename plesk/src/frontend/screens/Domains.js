// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useMemo,
    useState,
    Button,
    Label,
    List,
    ListEmptyView,
    Paragraph,
    SearchBar,
    Status,
    Text,
    Toolbar,
    ToolbarGroup,
} from '@plesk/ui-library';
import { post } from '../api';
import { code, t } from '../i18n';
import { number } from '../format';
import { ConfirmDialog, ErrorAlert, ListLoading, Mono, RefreshButton, runAction, Time, useAgent } from '../common';

const COVERAGE_INTENT = { full: 'success', partial: 'warning', none: 'danger', not_seen: 'inactive', unknown: 'inactive' };
const SCAN_INTENT = { clean: 'success', infected: 'danger', queued: 'info', scanning: 'info', never: 'inactive', failed: 'warning' };

const Domains = ({ status }) => {
    const sites = useAgent('sites');
    const [query, setQuery] = useState('');
    const [pending, setPending] = useState(null);

    const rows = useMemo(() => {
        const all = sites.data ? sites.data.sites : [];
        const q = query.toLowerCase();
        return q ? all.filter(s => `${s.domain} ${s.account} ${s.docroot}`.toLowerCase().includes(q)) : all;
    }, [sites.data, query]);

    const scan = () => runAction(post('scan', { docroot: pending.docroot }), t('domains.queued', { domain: pending.domain })).then(reply => {
        if (reply.ok || reply.error === 'scan_in_progress') {
            setPending(null);
            sites.reload();
        }
    });

    const busy = s => s.scan_status === 'queued' || s.scan_status === 'scanning';

    const columns = [
        {
            key: 'domain',
            title: t('domains.col.domain'),
            type: 'title',
            sortable: true,
            render: row => (
                <div>
                    <div>{row.domain || '–'}</div>
                    <Text intent="muted" fontSize="sm"><Mono>{row.docroot}</Mono></Text>
                </div>
            ),
        },
        { key: 'account', title: t('domains.col.account'), sortable: true, render: row => row.account || '–' },
        {
            key: 'coverage',
            title: t('domains.col.coverage'),
            render: row => <Label intent={COVERAGE_INTENT[row.coverage] || 'inactive'} view="light">{code('coverage', row.coverage)}</Label>,
        },
        {
            key: 'scan_status',
            title: t('domains.col.status'),
            render: row => (
                <Status intent={SCAN_INTENT[row.scan_status] || 'inactive'} compact progress={busy(row)}>
                    {code('scanStatus', row.scan_status)}
                </Status>
            ),
        },
        {
            key: 'last_scan',
            title: t('domains.col.lastScan'),
            render: row => (
                <span>
                    <Time value={row.last_scan} empty={t('domains.neverScanned')} />
                    {row.files ? <div><Text intent="muted" fontSize="sm">{t('domains.files', { count: number(row.files) })}</Text></div> : null}
                </span>
            ),
        },
        {
            key: 'scan',
            type: 'controls',
            align: 'right',
            render: row => (
                <Button
                    icon="scan"
                    disabled={!status.agent_running || busy(row)}
                    tooltip={busy(row) ? t('domains.alreadyQueued') : undefined}
                    onClick={() => setPending(row)}
                >
                    {t('domains.scanNow')}
                </Button>
            ),
        },
    ];

    return (
        <div>
            {sites.error ? <ErrorAlert error={sites.error} onRetry={sites.reload} status={status} /> : null}
            <Paragraph className="infrafence__intro">{t('domains.intro')}</Paragraph>
            {sites.error && !sites.data ? null : (
                <List
                    columns={columns}
                    data={rows}
                    rowKey="docroot"
                    filtered={!!query}
                    toolbar={(
                        <Toolbar>
                            <ToolbarGroup title={t('common.search')}>
                                <SearchBar
                                    inputProps={{ placeholder: t('domains.search'), value: query }}
                                    onTyping={value => setQuery(value)}
                                />
                            </ToolbarGroup>
                            <ToolbarGroup title={t('common.refresh')}>
                                <RefreshButton loading={sites.loading} onClick={sites.reload} />
                            </ToolbarGroup>
                        </Toolbar>
                    )}
                    emptyView={sites.loading && !sites.data ? <ListLoading /> : (
                        <ListEmptyView
                            title={query ? t('common.noMatches') : t('domains.empty')}
                            reason={query ? 'filtered' : undefined}
                        />
                    )}
                />
            )}
            <ConfirmDialog
                isOpen={!!pending}
                title={pending ? t('domains.confirmTitle', { domain: pending.domain || pending.docroot }) : ''}
                confirmText={t('domains.scanNow')}
                onConfirm={scan}
                onClose={() => setPending(null)}
            >
                <Paragraph>{t('domains.confirmText')}</Paragraph>
                {pending ? <Paragraph><Mono>{pending.docroot}</Mono></Paragraph> : null}
            </ConfirmDialog>
        </div>
    );
};

export default Domains;
