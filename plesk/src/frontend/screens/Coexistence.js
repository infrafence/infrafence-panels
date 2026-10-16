// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    Alert,
    List,
    ListEmptyView,
    Paragraph,
    Status,
    Text,
    Toolbar,
    ToolbarGroup,
} from '@plesk/ui-library';
import { code, t } from '../i18n';
import { ErrorAlert, ListLoading, RefreshButton, useAgent } from '../common';

const toolState = tool => {
    if (!tool.detected) {
        return <Status intent="inactive" compact>{t('coexistence.notFound')}</Status>;
    }
    return tool.running
        ? <Status intent="success" compact>{t('coexistence.running')}</Status>
        : <Status intent="warning" compact>{t('coexistence.installedStopped')}</Status>;
};

const Coexistence = ({ status }) => {
    const coexistence = useAgent('coexistence');
    const data = coexistence.data;

    // Detected tools first, then the ones that were looked for and not found.
    const tools = data ? [...data.tools].sort((a, b) => Number(!!b.detected) - Number(!!a.detected)) : [];

    const columns = [
        { key: 'name', title: t('coexistence.col.tool'), type: 'title', render: row => row.name || code('tool', row.id) },
        { key: 'state', title: t('coexistence.col.state'), render: toolState },
        {
            key: 'details',
            title: t('coexistence.col.details'),
            render: row => {
                const parts = [];
                if (row.version) {
                    parts.push(t('coexistence.version', { version: row.version }));
                }
                if (row.ruleset) {
                    parts.push(t('coexistence.ruleset', { ruleset: code('ruleset', row.ruleset) }));
                }
                return parts.length ? parts.join(' · ') : <span className="infrafence__muted">–</span>;
            },
        },
        {
            key: 'actions',
            title: t('coexistence.col.handling'),
            render: row => (
                <ul className={`infrafence__handling${row.detected ? '' : ' infrafence__muted'}`}>
                    {(row.actions || []).map(a => <li key={a}>{code('handling', a)}</li>)}
                </ul>
            ),
        },
    ];

    return (
        <div>
            {coexistence.error ? <ErrorAlert error={coexistence.error} onRetry={coexistence.reload} status={status} /> : null}
            {data ? (
                <Alert intent="info">
                    <Text bold>{code('mode', data.mode)}</Text>
                    {' – '}
                    {t(`modeText.${data.mode}`)}
                    {data.firewall_owner ? (
                        <div>{t('coexistence.firewallOwner', { tool: code('tool', data.firewall_owner) })}</div>
                    ) : null}
                </Alert>
            ) : null}
            <Paragraph className="infrafence__intro">{t('coexistence.intro')}</Paragraph>
            {coexistence.error && !coexistence.data ? null : (
                <List
                    columns={columns}
                    data={tools.map(tool => ({ ...tool, intent: tool.detected ? undefined : 'inactive' }))}
                    rowKey="id"
                    toolbar={(
                        <Toolbar>
                            <ToolbarGroup title={t('common.refresh')}>
                                <RefreshButton loading={coexistence.loading} onClick={coexistence.reload} />
                            </ToolbarGroup>
                        </Toolbar>
                    )}
                    emptyView={coexistence.loading && !data ? <ListLoading /> : <ListEmptyView title={t('coexistence.empty')} />}
                />
            )}
        </div>
    );
};

export default Coexistence;
