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
    Toolbar,
    ToolbarGroup,
} from '@plesk/ui-library';
import { code, t } from '../i18n';
import { ErrorAlert, ListLoading, Mono, RefreshButton, Time, useAgent } from '../common';

// Malware: critical, high, medium, low. File integrity and events: critical, warning, info.
export const SEVERITY_INTENT = { critical: 'danger', high: 'danger', medium: 'warning', warning: 'warning', low: 'info', info: 'inactive' };
const STATUS_INTENT = { detected: 'danger', quarantined: 'success' };
const SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, warning: 2, low: 3, info: 4 };

const Findings = ({ status }) => {
    const findings = useAgent('findings', { limit: 500 });
    const [kind, setKind] = useState('all');

    const rows = useMemo(() => {
        const all = findings.data ? findings.data.findings : [];
        return all
            .filter(f => kind === 'all' || f.kind === kind)
            .map(f => ({ ...f, key: `${f.kind}|${f.path}|${f.detected}` }));
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
            render: row => <div className="infrafence__path"><Mono>{row.path}</Mono></div>,
        },
        { key: 'kind', title: t('findings.col.kind'), render: row => code('kind', row.kind) },
        { key: 'name', title: t('findings.col.name'), render: row => row.name || <span className="infrafence__muted">–</span> },
        {
            key: 'status',
            title: t('findings.col.status'),
            render: row => <Label intent={STATUS_INTENT[row.status] || 'inactive'} view="light">{code('findingStatus', row.status)}</Label>,
        },
        { key: 'detected', title: t('findings.col.detected'), render: row => <Time value={row.detected} /> },
        { key: 'last_seen', title: t('findings.col.lastSeen'), render: row => <Time value={row.last_seen} /> },
    ];

    return (
        <div>
            {findings.error ? <ErrorAlert error={findings.error} onRetry={findings.reload} status={status} /> : null}
            <Paragraph className="infrafence__intro">{t('findings.intro')}</Paragraph>
            {findings.error && !findings.data ? null : (
                <List
                    columns={columns}
                    data={rows}
                    rowKey="key"
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
            {findings.data && findings.data.total > findings.data.findings.length ? (
                <Paragraph className="infrafence__muted">
                    {t('findings.more', { shown: findings.data.findings.length, total: findings.data.total })}
                </Paragraph>
            ) : null}
        </div>
    );
};

export default Findings;
