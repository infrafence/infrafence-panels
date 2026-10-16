<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

// JSON API for the extension UI: api.php?action=<action>.
//
// Plesk's SDK middleware runs first: a Plesk session is required (400/401 without one), the user
// must be the administrator (403 otherwise), and every POST must carry the session's forgery
// protection token in X-Forgery-Protection-Token (403 if it is missing or does not match).
// Only then does Modules_Infrafence_Api see the request.

use Plesk\SDK\Middleware\Access\Csrf;
use Plesk\SDK\Middleware\Access\Session;
use Plesk\SDK\Middleware\Access\UserRole;
use Psr\Http\Message\ResponseFactoryInterface;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;

pm_Context::init('infrafence');

// One deadline for all the agent calls of this request (a change makes up to four), kept well
// below PHP's own time limit so that the reply is always sent.
$limit = (int)ini_get('max_execution_time');
Modules_Infrafence_Agent::setDeadline(microtime(true) + ($limit > 0 ? min(50, max(5, $limit - 10)) : 50));

$factory = new Laminas\Diactoros\ResponseFactory();

$api = new class($factory) implements RequestHandlerInterface {
    private $factory;

    public function __construct(ResponseFactoryInterface $factory)
    {
        $this->factory = $factory;
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $query = $request->getQueryParams();
        $body = json_decode((string)$request->getBody(), true);
        [$status, $data] = (new Modules_Infrafence_Api())->handle(
            $request->getMethod(),
            is_string($query['action'] ?? null) ? $query['action'] : '',
            $query,
            is_array($body) ? $body : []
        );
        $response = $this->factory->createResponse($status);
        $response->getBody()->write(json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));

        return $response->withHeader('Content-Type', 'application/json; charset=utf-8');
    }
};

$pipeline = array_reverse([
    (new Session($factory))->setExternalSessionAllowed(true),
    new UserRole($factory, [UserRole::ROLE_ADMIN]),
    new Csrf($factory),
]);
$handler = $api;
foreach ($pipeline as $middleware) {
    $handler = new class($middleware, $handler) implements RequestHandlerInterface {
        private $middleware;
        private $next;

        public function __construct(MiddlewareInterface $middleware, RequestHandlerInterface $next)
        {
            $this->middleware = $middleware;
            $this->next = $next;
        }

        public function handle(ServerRequestInterface $request): ResponseInterface
        {
            return $this->middleware->process($request, $this->next);
        }
    };
}

$response = $handler->handle(Laminas\Diactoros\ServerRequestFactory::fromGlobals());

http_response_code($response->getStatusCode());
foreach ($response->getHeaders() as $name => $values) {
    header($name . ': ' . implode(', ', $values));
}
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
echo $response->getBody();
