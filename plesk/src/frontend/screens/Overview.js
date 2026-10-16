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
import { number } from '../format';
import { Mono, RefreshButton, Time, useAgent } from '../common';

const DASH = '–';

const protection = status => {
    if (!status.agent_running) {
        return { intent: 'danger', text: t('overview.state.stopped') };
    }
    if (status.suspended) {
        return { intent: 'danger', text: t('overview.state.suspended') };
    }
    if (!status.connected) {
        return { intent: 'warning', text: t('overview.state.disconnected') };
    }
    if (status.monitor_mode) {
        return { intent: 'warning', text: t('overview.state.monitor') };
    }
    return { intent: 'success', text: t('overview.state.protected') };
};

/**
 * AutoMode is the object the dashboard sends, passed through by the agent, or null. Today's
 * dashboards send null; a known on/off or state field is shown when present.
 */
const automode = value => {
    if (value === null || value === undefined || typeof value !== 'object') {
        return { intent: 'inactive', text: t('overview.automodeNotReported') };
    }
    if (typeof value.enabled === 'boolean') {
        return value.enabled
            ? { intent: 'success', text: t('automode.on') }
            : { intent: 'inactive', text: t('automode.off') };
    }
    const state = typeof value.state === 'string' ? value.state : value.mode;
    if (typeof state === 'string' && state) {
        return { intent: 'info', text: code('automode', state) };
    }
    return { intent: 'info', text: t('overview.automodeSet') };
};

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
    const events = useAgent('events', { limit: 500, since: '24h' });

    const open = findings.data ? findings.data.findings.filter(f => f.status === 'detected') : null;
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
                    value={running && bans.data ? number(bans.data.total) : DASH}
                    label={t('overview.glance.bans')}
                    onClick={() => go('bans')}
                />
                <Count
                    value={running && open ? number(open.length) : DASH}
                    label={t('overview.glance.findings')}
                    intent={critical > 0 ? 'danger' : undefined}
                    hint={critical > 0 ? t('overview.glance.critical', { count: critical }) : null}
                    onClick={() => go('findings')}
                />
                <Count
                    value={running && events.data ? number(events.data.events.length) : DASH}
                    label={t('overview.glance.events')}
                    onClick={() => go('events')}
                />
            </div>
        </Panel>
    );
};

const Overview = ({ status, reloadStatus, go }) => {
    const state = protection(status);
    const auto = automode(status.automode);
    let mode = DASH;
    if (status.monitor_mode === true) {
        mode = t('overview.modeMonitor');
    } else if (status.monitor_mode === false) {
        mode = t('overview.modeEnforce');
    }

    return (
        <Grid xs={1} md={2} gap="md">
            <GridCol>
                <Panel title={t('overview.protection.title')} extra={<RefreshButton onClick={reloadStatus} />}>
                    <div className="infrafence__headline">
                        <Status intent={state.intent}>{state.text}</Status>
                    </div>
                    <Section>
                        <SectionItem title={t('overview.field.agent')}>
                            {status.version ? t('overview.agentVersion', { version: status.version }) : DASH}
                            {' · '}
                            {status.agent_running ? t('overview.running') : t('overview.notRunning')}
                        </SectionItem>
                        <SectionItem title={t('overview.field.connection')}>
                            {status.connected ? t('overview.connected') : t('overview.notConnected')}
                        </SectionItem>
                        <SectionItem title={t('overview.field.heartbeat')}>
                            <Time value={status.last_heartbeat} empty={DASH} />
                        </SectionItem>
                        <SectionItem title={t('overview.field.sync')}>
                            <Time value={status.last_sync} empty={DASH} />
                        </SectionItem>
                        <SectionItem title={t('overview.field.mode')}>{mode}</SectionItem>
                        <SectionItem title={t('overview.field.plan')}>{status.plan ? code('plan', status.plan) : DASH}</SectionItem>
                        <SectionItem title={t('overview.field.automode')}>
                            <Status intent={auto.intent} compact>{auto.text}</Status>
                            <div><Hint>{t('overview.automodeHint')}</Hint></div>
                        </SectionItem>
                        {status.agent_id !== null && status.agent_id !== undefined ? (
                            <SectionItem title={t('overview.field.agentId')}><Mono>{String(status.agent_id)}</Mono></SectionItem>
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
