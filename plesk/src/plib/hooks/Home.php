<?php
// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

// Plesk SDK hooks are declared by returning an anonymous class.
return new class extends \Plesk\SDK\Hook\Home {
    public function getBlocks(): array
    {
        return [new Modules_Infrafence_HomeBlock()];
    }
};
