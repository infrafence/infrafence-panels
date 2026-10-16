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
    SegmentedControl,
    Status,
    Text,
    Toolbar,
    ToolbarGroup,
} from '@plesk/ui-library';
import { code, t } from '../i18n';
import { ErrorAlert, ListLoading, Mono, RefreshButton, Time, useAgent } from '../common';

export const SEVERITY_INTENT = { critical: 'danger', high: 'danger', medium: 'warning', low: 'info', info: 'inactive' };
const STATUS_INTENT = { open: 'danger', quarantined: 'warning', acknowledged: 'info', resolved: 'success', ignored: 'inactive' };
const SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, low: 3, info: 4 };

const Findings = ({ status }) => {
    const findings = useAgent('findings', { limit: 500 });
    const [kind, setKind] = useState('all');

    const rows = useMemo(() => {
        const all = findings.data ? findings.data.findings : [];
        return all.filter(f => kind === 'all' || f.kind === kind);
    }, [findings.data, kind]);

    const columns = [
        {
            key: 'severity',
            title: t('findings.col.severity'),
            sortable: true,
            sort: (a, b) => Math.sign((SEVERITY_ORDER[a.severity] ?? 9) - (SEVERITY_ORDER[b.severity] ?? 9)),
            render: row => <Status intent={SEVERITY_INTENT[row.severity] || 'inactive'} compact>{code('severity', row.severity)}</Status>,
        },
        {
            key: 'path',
            title: t('findings.col.path'),
            type: 'title',
            render: row => (
                <div className="infrafence__path">
                    <Mono>{row.path}</Mono>
                    {row.domain ? <div><Text intent="muted" fontSize="sm">{row.domain}</Text></div> : null}
                </div>
            ),
        },
        { key: 'kind', title: t('findings.col.kind'), render: row => code('kind', row.kind) },
        { key: 'signature', title: t('findings.col.signature'), render: row => (row.signature ? <Mono>{row.signature}</Mono> : '–') },
        {
            key: 'status',
            title: t('findings.col.status'),
            render: row => <Label intent={STATUS_INTENT[row.status] || 'inactive'} view="light">{code('findingStatus', row.status)}</Label>,
        },
        { key: 'detected', title: t('findings.col.detected'), sortable: true, render: row => <Time value={row.detected} /> },
    ];

    return (
        <div>
            {findings.error ? <ErrorAlert error={findings.error} onRetry={findings.reload} status={status} /> : null}
            <Paragraph className="infrafence__intro">{t('findings.intro')}</Paragraph>
            {findings.error && !findings.data ? null : (
                <List
                    columns={columns}
                    data={rows}
                    rowKey="id"
                    sortColumn="detected"
                    sortDirection="DESC"
                    filtered={kind !== 'all'}
                    toolbar={(
                        <Toolbar>
                            <ToolbarGroup title={t('findings.filter')}>
                                <SegmentedControl
                                    buttons={[
                                        { value: 'all', title: t('findings.all') },
                                        { value: 'malware', title: t('kind.malware') },
                                        { value: 'integrity', title: t('kind.integrity') },
                                    ]}
                                    selected={kind}
                                    onChange={setKind}
                                />
                            </ToolbarGroup>
                            <ToolbarGroup title={t('common.refresh')}>
                                <RefreshButton loading={findings.loading} onClick={findings.reload} />
                                {status.dashboard_url ? (
                                    <Button
                                        ghost
                                        component="a"
                                        href={status.dashboard_url}
                                        target="_blank"
                                        rel="noopener noreferrer"
                                        icon="arrow-diagonal-out"
                                    >
                                        {t('findings.manage')}
                                    </Button>
                                ) : null}
                            </ToolbarGroup>
                        </Toolbar>
                    )}
                    emptyView={findings.loading && !findings.data ? <ListLoading /> : (
                        <ListEmptyView
                            title={kind === 'all' ? t('findings.empty') : t('common.noMatches')}
                            description={kind === 'all' ? t('findings.emptyHint') : null}
                            reason={kind === 'all' ? undefined : 'filtered'}
                        />
                    )}
                />
            )}
        </div>
    );
};

export default Findings;
