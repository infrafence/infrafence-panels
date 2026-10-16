<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

/**
 * Ends an API request early with an HTTP status and a JSON body.
 */
class Modules_Infrafence_ApiError extends Exception
{
    /** @var array */
    public $data;

    public function __construct(int $status, array $data)
    {
        parent::__construct((string)($data['error'] ?? 'error'), $status);
        $this->data = $data;
    }

    public static function code(int $status, string $error): self
    {
        return new self($status, Modules_Infrafence_Agent::error($error));
    }
}
