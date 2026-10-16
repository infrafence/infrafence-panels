// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    useEffect,
    useState,
    Alert,
    Skeleton,
    SkeletonText,
    Tab,
    Tabs,
} from '@plesk/ui-library';
import { t } from './i18n';
import { ErrorAlert, ToastHost, useAgent } from './common';
import Overview from './screens/Overview';
import Bans from './screens/Bans';
import AllowList from './screens/AllowList';
import Findings from './screens/Findings';
import Events from './screens/Events';
import Coexistence from './screens/Coexistence';
import Domains from './screens/Domains';
import NotInstalled from './screens/NotInstalled';

const SCREENS = [
    { id: 'overview', component: Overview },
    { id: 'bans', component: Bans },
    { id: 'allowlist', component: AllowList },
    { id: 'findings', component: Findings },
    { id: 'events', component: Events },
    { id: 'coexistence', component: Coexistence },
    { id: 'domains', component: Domains },
];

const screenFromHash = fallback => {
    const id = window.location.hash.replace(/^#/, '');
    return SCREENS.some(s => s.id === id) ? id : fallback;
};

const AgentState = ({ status }) => {
    if (!status.agent_running) {
        return <Alert intent="danger">{t('agent.stopped')}</Alert>;
    }
    if (!status.connected) {
        return <Alert intent="warning">{t('agent.disconnected')}</Alert>;
    }
    return null;
};

const App = ({ screen: initialScreen, installCommand, dashboardUrl }) => {
    const [screen, setScreen] = useState(() => screenFromHash(initialScreen));
    const status = useAgent('status');

    useEffect(() => {
        const onHash = () => setScreen(screenFromHash('overview'));
        window.addEventListener('hashchange', onHash);
        return () => window.removeEventListener('hashchange', onHash);
    }, []);

    const go = id => {
        if (window.location.hash !== `#${id}`) {
            window.history.pushState(null, '', `#${id}`);
        }
        setScreen(id);
    };

    if (status.loading && !status.data && !status.error) {
        return (
            <div className="infrafence__loading">
                <Skeleton height={40} />
                <SkeletonText lines={4} />
            </div>
        );
    }

    if (status.error === 'agent_not_installed') {
        return (
            <div className="infrafence__app">
                <NotInstalled installCommand={installCommand} dashboardUrl={dashboardUrl} onCheckAgain={status.reload} checking={status.loading} />
                <ToastHost />
            </div>
        );
    }

    if (!status.data) {
        return <ErrorAlert error={status.error} onRetry={status.reload} />;
    }

    const active = SCREENS.findIndex(s => s.id === screen);
    const Screen = SCREENS[active].component;

    return (
        <div className="infrafence__app">
            <Tabs active={active + 1}>
                {SCREENS.map(s => (
                    <Tab
                        key={s.id}
                        title={t(`tabs.${s.id}`)}
                        href={`#${s.id}`}
                        onClick={e => e.preventDefault()}
                        onActivate={() => go(s.id)}
                    />
                ))}
            </Tabs>
            <div className="infrafence__screen">
                <AgentState status={status.data} />
                <Screen status={status.data} reloadStatus={status.reload} go={go} dashboardUrl={dashboardUrl} />
            </div>
            <ToastHost />
        </div>
    );
};

export default App;
