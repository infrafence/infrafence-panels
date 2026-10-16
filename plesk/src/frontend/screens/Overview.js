// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    Button,
    Grid,
    GridCol,
    Hint,
    Link,
    Panel,
    Section,
    SectionItem,
    Status,
    Text,
} from '@plesk/ui-library';
import { code, t } from '../i18n';
import { ageSeconds, number } from '../format';
import { Mono, RefreshButton, Time, useAgent } from '../common';

const STALE_HEARTBEAT_SECONDS = 300;

const protection = status => {
    if (!status.agent_running) {
        return { intent: 'danger', text: t('overview.state.stopped') };
    }
    if (!status.connected) {
        return { intent: 'warning', text: t('overview.state.disconnected') };
    }
    if (ageSeconds(status.last_heartbeat) > STALE_HEARTBEAT_SECONDS) {
        return { intent: 'warning', text: t('overview.state.stale') };
    }
    return { intent: 'success', text: t('overview.state.protected') };
};

const AUTOMODE_INTENT = { enforce: 'success', observe: 'info', off: 'inactive' };

const Count = ({ value, label, hint, onClick, intent }) => (
    <div className="infrafence__count">
        <Link onClick={onClick} className="infrafence__count-value">
            <Text intent={intent}>{value}</Text>
        </Link>
        <div>{label}</div>
        {hint ? <Hint>{hint}</Hint> : null}
    </div>
);

const Glance = ({ running, go }) => {
    const bans = useAgent('bans', { limit: 1 });
    const findings = useAgent('findings', { limit: 500 });
    const events = useAgent('events', { limit: 1000, since: '24h' });

    const dash = '–';
    const open = findings.data ? findings.data.findings.filter(f => f.status === 'open') : null;
    const critical = open ? open.filter(f => f.severity === 'critical').length : 0;

    return (
        <Panel
            title={t('overview.glance.title')}
            extra={(
                <RefreshButton
                    loading={bans.loading || findings.loading || events.loading}
                    onClick={() => { bans.reload(); findings.reload(); events.reload(); }}
                />
            )}
        >
            <div className="infrafence__counts">
                <Count
                    value={running && bans.data ? number(bans.data.total ?? bans.data.bans.length) : dash}
                    label={t('overview.glance.bans')}
                    onClick={() => go('bans')}
                />
                <Count
                    value={running && open ? number(open.length) : dash}
                    label={t('overview.glance.findings')}
                    intent={critical > 0 ? 'danger' : undefined}
                    hint={critical > 0 ? t('overview.glance.critical', { count: critical }) : null}
                    onClick={() => go('findings')}
                />
                <Count
                    value={running && events.data ? number(events.data.events.length) : dash}
                    label={t('overview.glance.events')}
                    onClick={() => go('events')}
                />
            </div>
        </Panel>
    );
};

const Overview = ({ status, reloadStatus, go }) => {
    const state = protection(status);

    return (
        <Grid xs={1} md={2} gap="md">
            <GridCol>
                <Panel title={t('overview.protection.title')} extra={<RefreshButton onClick={reloadStatus} />}>
                    <div className="infrafence__headline">
                        <Status intent={state.intent}>{state.text}</Status>
                    </div>
                    <Section>
                        <SectionItem title={t('overview.field.agent')}>
                            {status.agent_version ? t('overview.agentVersion', { version: status.agent_version }) : '–'}
                            {' · '}
                            {status.agent_running ? t('overview.running') : t('overview.notRunning')}
                        </SectionItem>
                        <SectionItem title={t('overview.field.heartbeat')}>
                            <Time value={status.last_heartbeat} empty={t('overview.never')} />
                        </SectionItem>
                        <SectionItem title={t('overview.field.connection')}>
                            {status.connected ? t('overview.connected') : t('overview.notConnected')}
                        </SectionItem>
                        <SectionItem title={t('overview.field.plan')}>{code('plan', status.plan) || '–'}</SectionItem>
                        <SectionItem title={t('overview.field.automode')}>
                            <Status intent={AUTOMODE_INTENT[status.automode] || 'inactive'} compact>
                                {code('automode', status.automode) || '–'}
                            </Status>
                            <div><Hint>{t(`automodeHint.${status.automode}`)}</Hint></div>
                        </SectionItem>
                        {status.hostname ? (
                            <SectionItem title={t('overview.field.server')}>{status.hostname}</SectionItem>
                        ) : null}
                        {status.agent_id ? (
                            <SectionItem title={t('overview.field.agentId')}><Mono>{status.agent_id}</Mono></SectionItem>
                        ) : null}
                    </Section>
                    <div className="infrafence__actions">
                        <Button
                            component="a"
                            href={status.dashboard_url || undefined}
                            target="_blank"
                            rel="noopener noreferrer"
                            intent="primary"
                            icon="arrow-diagonal-out"
                            disabled={!status.dashboard_url}
                        >
                            {t('common.openInInfrafence')}
                        </Button>
                        <Hint>{t('overview.loginHint')}</Hint>
                    </div>
                </Panel>
            </GridCol>
            <GridCol>
                <Glance running={status.agent_running} go={go} />
            </GridCol>
        </Grid>
    );
};

export default Overview;
