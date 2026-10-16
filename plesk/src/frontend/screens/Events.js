// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useState,
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
import { dateTime } from '../format';
import { ErrorAlert, ListLoading, Mono, RefreshButton, Time, useAgent } from '../common';
import { SEVERITY_INTENT } from './Findings';

const PERIODS = ['24h', '7d', '30d'];

const Events = ({ status }) => {
    const [since, setSince] = useState('24h');
    const events = useAgent('events', { limit: 500, since });

    const columns = [
        {
            key: 'time',
            title: t('events.col.time'),
            render: row => <span title={dateTime(row.time)}><Time value={row.time} /></span>,
        },
        { key: 'type', title: t('events.col.type'), type: 'title', render: row => code('event', row.type) },
        {
            key: 'severity',
            title: t('events.col.severity'),
            render: row => <Status intent={SEVERITY_INTENT[row.severity] || 'inactive'} compact>{code('severity', row.severity)}</Status>,
        },
        { key: 'source_ip', title: t('events.col.ip'), render: row => (row.source_ip ? <Mono>{row.source_ip}</Mono> : <span className="infrafence__muted">–</span>) },
        {
            key: 'source',
            title: t('events.col.origin'),
            render: row => (
                <span>
                    {code('origin', row.source)}
                    {row.actor ? <Text intent="muted">{` · ${row.actor}`}</Text> : null}
                </span>
            ),
        },
    ];

    return (
        <div>
            {events.error ? <ErrorAlert error={events.error} onRetry={events.reload} status={status} /> : null}
            <Paragraph className="infrafence__intro">{t('events.intro')}</Paragraph>
            {events.error && !events.data ? null : (
                <List
                    columns={columns}
                    data={events.data ? events.data.events : []}
                    rowKey="id"
                    toolbar={(
                        <Toolbar>
                            <ToolbarGroup title={t('events.period')}>
                                <SegmentedControl
                                    buttons={PERIODS.map(p => ({ value: p, title: t(`events.since.${p}`) }))}
                                    selected={since}
                                    onChange={setSince}
                                />
                            </ToolbarGroup>
                            <ToolbarGroup title={t('common.refresh')}>
                                <RefreshButton loading={events.loading} onClick={events.reload} />
                            </ToolbarGroup>
                        </Toolbar>
                    )}
                    emptyView={events.loading && !events.data ? <ListLoading /> : (
                        <ListEmptyView title={t('events.empty')} />
                    )}
                />
            )}
        </div>
    );
};

export default Events;
