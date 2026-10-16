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
import { code, has, locale, t } from '../i18n';
import { ErrorAlert, ListLoading, RefreshButton, useAgent } from '../common';

/**
 * What InfraFence does about a tool. The agent sends it in English with an `action_id`; it is
 * translated by that id, and shown as sent for English or for an id this version does not know.
 */
const actionText = tool => {
    const key = `coexistAction.${tool.action_id}`;
    return locale() !== 'en-US' && has(key) ? t(key) : tool.action;
};

const Coexistence = ({ status }) => {
    const coexistence = useAgent('coexistence');
    const data = coexistence.data;
    const tools = data ? data.tools : [];
    const firewallTools = tools.filter(tool => tool.manages_firewall && tool.active).map(tool => tool.name);

    const columns = [
        { key: 'name', title: t('coexistence.col.tool'), type: 'title', render: row => row.name },
        { key: 'kind', title: t('coexistence.col.kind'), render: row => code('toolKind', row.kind) },
        {
            key: 'active',
            title: t('coexistence.col.state'),
            render: row => (row.active
                ? <Status intent="success" compact>{t('coexistence.active')}</Status>
                : <Status intent="inactive" compact>{t('coexistence.inactive')}</Status>),
        },
        {
            key: 'details',
            title: t('coexistence.col.details'),
            render: row => {
                const parts = [];
                if (row.version) {
                    parts.push(t('coexistence.version', { version: row.version }));
                }
                if (row.rulesets && row.rulesets.length) {
                    parts.push(t('coexistence.rulesets', { rulesets: row.rulesets.join(', ') }));
                }
                if (row.manages_firewall) {
                    parts.push(t('coexistence.managesFirewall'));
                }
                return parts.length ? parts.map(p => <div key={p}>{p}</div>) : <span className="infrafence__muted">–</span>;
            },
        },
        { key: 'action', title: t('coexistence.col.handling'), render: row => actionText(row) },
    ];

    return (
        <div>
            {coexistence.error ? <ErrorAlert error={coexistence.error} onRetry={coexistence.reload} status={status} /> : null}
            {data ? (
                <Alert intent="info">
                    <Text bold>{code('mode', data.mode)}</Text>
                    {' – '}
                    {t(`modeText.${data.mode}`)}
                    {firewallTools.length ? (
                        <div>{t('coexistence.firewallTools', { tools: firewallTools.join(', ') })}</div>
                    ) : null}
                </Alert>
            ) : null}
            <Paragraph className="infrafence__intro">{t('coexistence.intro')}</Paragraph>
            {coexistence.error && !data ? null : (
                <List
                    columns={columns}
                    data={tools.map(tool => ({ ...tool, intent: tool.active ? undefined : 'inactive' }))}
                    rowKey="id"
                    toolbar={(
                        <Toolbar>
                            <ToolbarGroup title={t('common.refresh')}>
                                <RefreshButton loading={coexistence.loading} onClick={coexistence.reload} />
                            </ToolbarGroup>
                        </Toolbar>
                    )}
                    emptyView={coexistence.loading && !data ? <ListLoading /> : (
                        <ListEmptyView title={t('coexistence.empty')} description={t('coexistence.emptyHint')} />
                    )}
                />
            )}
        </div>
    );
};

export default Coexistence;
