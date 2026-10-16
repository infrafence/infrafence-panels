// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useMemo,
    useState,
    Alert,
    Button,
    Label,
    List,
    ListEmptyView,
    Paragraph,
    SearchBar,
    Text,
    Toolbar,
    ToolbarGroup,
} from '@plesk/ui-library';
import { post } from '../api';
import { code, errorText, sentences, t } from '../i18n';
import { ConfirmDialog, ErrorAlert, ListLoading, Mono, RefreshButton, toast, useAgent } from '../common';

const Domains = ({ status }) => {
    const sites = useAgent('sites');
    const [query, setQuery] = useState('');
    const [pending, setPending] = useState(null);

    const all = sites.data ? sites.data.sites : [];
    const rows = useMemo(() => {
        const q = query.toLowerCase();
        return q ? all.filter(s => `${s.domain} ${s.account || ''} ${s.document_root || ''}`.toLowerCase().includes(q)) : all;
    }, [all, query]);
    // Plesk sites are all "site"; the column is shown only for panels with several kinds.
    const showKind = all.some(s => s.kind !== 'site');
    const running = sites.data ? sites.data.agent_running : status.agent_running;

    const scan = () => post('scan', { document_root: pending.document_root }).then(reply => {
        if (reply.ok) {
            toast('success', sentences(
                t('domains.queued', { domain: pending.domain }),
                reply.reported === false ? t('result.notReported') : '',
            ));
        } else {
            toast(reply.error === 'scan_running' ? 'warning' : 'danger', errorText(reply.error));
        }
        if (reply.ok || ['scan_running', 'not_a_document_root', 'not_scannable'].includes(reply.error)) {
            setPending(null);
        }
    });

    const columns = [
        {
            key: 'domain',
            title: t('domains.col.domain'),
            type: 'title',
            render: row => (
                <div>
                    <div>{row.domain}</div>
                    <Text intent="muted" fontSize="sm">
                        {row.document_root ? <Mono>{row.document_root}</Mono> : t('domains.noDocumentRoot')}
                    </Text>
                </div>
            ),
        },
        { key: 'account', title: t('domains.col.account'), render: row => row.account || <span className="infrafence__muted">–</span> },
        ...(showKind ? [{ key: 'kind', title: t('domains.col.kind'), render: row => code('siteKind', row.kind) }] : []),
        {
            key: 'scan_covered',
            title: t('domains.col.coverage'),
            render: row => (row.scan_covered
                ? <Label intent="success" view="light">{t('domains.covered')}</Label>
                : <Label intent="warning" view="light">{t('domains.notCovered')}</Label>),
        },
        {
            key: 'scan',
            type: 'controls',
            align: 'right',
            // The agent says in advance which document roots it accepts (they belong to the site's account).
            render: row => (!row.scannable ? (
                <span className="infrafence__muted" title={t('domains.notScannableHint')}>{t('domains.notScannable')}</span>
            ) : (
                <Button
                    icon="scan"
                    disabled={!running || !row.document_root}
                    tooltip={running ? undefined : t('domains.needsAgent')}
                    onClick={() => setPending(row)}
                >
                    {t('domains.scanNow')}
                </Button>
            )),
        },
    ];

    return (
        <div>
            {sites.error ? <ErrorAlert error={sites.error} onRetry={sites.reload} status={status} /> : null}
            {sites.data && sites.data.malware_scan_enabled === false ? <Alert intent="warning">{t('domains.scheduledOff')}</Alert> : null}
            <Paragraph className="infrafence__intro">{t('domains.intro')}</Paragraph>
            {sites.error && !sites.data ? null : (
                <List
                    columns={columns}
                    data={rows}
                    rowKey="domain"
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
                title={pending ? t('domains.confirmTitle', { domain: pending.domain }) : ''}
                confirmText={t('domains.scanNow')}
                onConfirm={scan}
                onClose={() => setPending(null)}
            >
                <Paragraph>{t('domains.confirmText')}</Paragraph>
                {pending ? <Paragraph><Mono>{pending.document_root}</Mono></Paragraph> : null}
            </ConfirmDialog>
        </div>
    );
};

export default Domains;
