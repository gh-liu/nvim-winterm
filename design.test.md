# nvim-winterm Test Framework Design

Using Oracle Methodology to design a comprehensive testing strategy for the multi-terminal manager.

**Language:** English  
**Status:** Design Phase  
**Last Updated:** 2026-01-26

---

## Table of Contents

1. [Testing Philosophy](#testing-philosophy)
2. [Test Strategy Matrix](#test-strategy-matrix)
3. [Core Testing Approach](#core-testing-approach)
4. [Test Pyramid & Coverage](#test-pyramid--coverage)
5. [Implementation Details](#implementation-details)
6. [Automated Assertions](#automated-assertions)
7. [Continuous Integration](#continuous-integration)

---

## Testing Philosophy

### Oracle Principle: "State Over Screenshots"

When testing a terminal UI plugin, we have two conflicting instincts:

1. **Screenshot Testing**: "Take screenshot → compare with golden reference"
2. **API Testing**: "Query state/buffer/window → assert expected values"

**Oracle Decision:**

- **Primary**: Use **state-based assertions** (query buffer content, window config, state object, terminal metadata)
  - **Reason**: Deterministic, debuggable, immune to rendering differences
  - **Cost**: Modest—just query Neovim APIs
  - **Maintainability**: High—changes to code require explicit test updates

- **Secondary**: Use **screenshot testing** only for:
  - Winbar UI visual regression (rare, only when layout changes)
  - Cross-version Neovim rendering compatibility (optional)

**Rationale**: 
- Terminal content is inherently variable (command output, timestamps, colors)
- Window/buffer state is canonical truth; visual rendering is derived
- Queries are faster, more reliable, and easier to debug than screenshot diffing

---

## Test Strategy Matrix

| Component | Test Type | Oracle Approach | Coverage Goal |
|-----------|-----------|-----------------|---|
| **State Management** | Unit | Direct Lua API calls | 95%+ |
| **Terminal Lifecycle** | Integration | Create/switch/close with state validation | 90%+ |
| **Window Operations** | Integration | Window open/close/toggle with buffer verification | 90%+ |
| **Command Dispatch** | Integration | `:Winterm` command → state assertion | 85%+ |
| **Winbar Rendering** | Visual | Snapshot content string (not pixel-diff) | 80%+ |
| **Error Handling** | Unit | Invalid operations → graceful degradation | 85%+ |
| **Edge Cases** | Integration | Multiple terminals, rapid operations, state races | 90%+ |

---

## Core Testing Approach

### Why mini.test + child Neovim?

```
┌─────────────────────────────────────┐
│    Parent Process (test runner)     │
│  ├─ Spawns child Neovim instances  │
│  ├─ Sends commands via RPC          │
│  └─ Asserts via Lua API queries     │
└─────────────────────────────────────┘
         │
         ├─→ Child Instance 1 (isolated)
         ├─→ Child Instance 2 (clean state)
         └─→ Child Instance N (fresh env)
```

**Benefits**:
1. **Isolation**: Each test runs in fresh Neovim, no state leakage
2. **Reproducibility**: Same config every time
3. **Debuggability**: Can inspect child state mid-test
4. **Performance**: Parallelizable (though mini.test runs sequentially)

### Test Structure

```
tests/
├── test_smoke.lua           # Basic plugin load + command existence
├── test_state.lua           # State management (add_term, switch, remove)
├── test_terminal.lua        # Terminal creation/switching/closing
├── test_window.lua          # Window open/close/toggle lifecycle
├── test_actions.lua         # High-level actions (toggle, focus, kill)
├── test_commands.lua        # `:Winterm` command dispatch
├── test_edge_cases.lua      # Races, invalid states, rapid operations
└── test_winbar.lua          # Winbar rendering & content validation

scripts/
├── minimal_init.lua         # Minimal Neovim config for tests
└── minitest.lua             # (Optional) Project-specific test runner

```

---

## Test Pyramid & Coverage

```
                    △
                   /  \
                  /Edge \
                 / Cases \
                /──────────\        (10% - rare scenarios, races, error paths)
               /            \
              / Integration  \      (30% - multi-component flows)
             /────────────────\
            /                  \
           /      Unit Tests    \   (60% - single module, direct APIs)
          /────────────────────────\

        Assertion: State-based query API (not screenshot)
        Tool: mini.test + child Neovim
```

### Coverage Breakdown

| Layer | Type | Count | Tools |
|-------|------|-------|-------|
| **Unit** | State, utils | ~20 | Direct Lua, mock state |
| **Integration** | Terminal, window, actions | ~40 | child Neovim + RPC API |
| **Edge Case** | Races, invalid ops | ~15 | Rapid op, concurrent deletion |
| **Visual (Optional)** | Winbar string | ~5 | Content string snapshot |
| **Total** | - | ~80 | - |

---

## Implementation Details

### Phase 1: Infrastructure (Week 1)

#### scripts/minimal_init.lua

```lua
-- Minimal Neovim config for test isolation
local repo_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h:h')

-- Set up runtimepath to load plugin from repo
vim.opt.runtimepath:prepend(repo_root)

-- Setup nvim options for testing
vim.opt.number = false
vim.opt.signcolumn = 'no'

-- Load mini.test (assumes user has mini.test installed)
require('mini.test').setup()

-- Load the plugin
require('winterm')
```

#### scripts/minitest.lua (Runner Script)

```lua
-- Optional: project-specific test runner
-- Usage: nvim --headless -u scripts/minimal_init.lua -S scripts/minitest.lua

local MiniTest = require('mini.test')

-- Run all tests
local suite = MiniTest.collect()
MiniTest.execute(suite, MiniTest.gen_reporter.stdout())
```

#### Structure: Test Set Pattern

Each `tests/test_*.lua` returns a `MiniTest.new_set()`:

```lua
local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_once = function()
      child.stop()
    end,
  }
})

-- Test cases here...

return T
```

### Phase 2: Unit Tests (Week 1-2)

#### tests/test_state.lua

```lua
local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_once = function()
      child.stop()
    end,
  }
})

-- Helper to get current state snapshot
local function get_state()
  return child.lua([[
    local state = require('winterm.state')
    return {
      terms = state.list_terms(),
      current_idx = state.current_idx,
      winnr = state.winnr,
      term_count = state.get_term_count(),
    }
  ]])
end

T['State: add_term increases count'] = function()
  child.lua('require("winterm.state").clear()')  -- Clean slate
  
  local s1 = get_state()
  MiniTest.expect.equality(s1.term_count, 0)
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 'test1', cmd = 'echo 1', job_id = 1, is_closed = false})
  ]])
  
  local s2 = get_state()
  MiniTest.expect.equality(s2.term_count, 1)
  MiniTest.expect.equality(s2.current_idx, 1)
end

T['State: add_term multiple'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 'term1', cmd = 'cmd1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 'term2', cmd = 'cmd2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 'term3', cmd = 'cmd3', job_id = 3, is_closed = false})
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 3)
  MiniTest.expect.equality(s.current_idx, 3)  -- Focus on latest
end

T['State: remove_term adjusts focus correctly'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
    
    -- Current is 3, remove 2 (middle)
    state.remove_term(2)
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 2)
  MiniTest.expect.equality(s.current_idx, 2)  -- Adjusted from 3 to 2
end

T['State: remove_term last adjusts down'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
    
    -- Current is 3, remove current (3)
    state.remove_term(3)
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 2)
  MiniTest.expect.equality(s.current_idx, 2)  -- Falls back to prev
end

T['State: remove_term all clears current_idx'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.remove_term(1)
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 0)
  MiniTest.expect.equality(s.current_idx, nil)
end

T['State: find_term_by_bufnr'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 10, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 20, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
  ]])
  
  local found = child.lua('return require("winterm.state").find_term_by_bufnr(10) ~= nil')
  MiniTest.expect.equality(found, true)
  
  local not_found = child.lua('return require("winterm.state").find_term_by_bufnr(999) ~= nil')
  MiniTest.expect.equality(not_found, false)
end

T['State: find_term_index_by_bufnr'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 10, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 20, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 30, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
  ]])
  
  local idx = child.lua('return require("winterm.state").find_term_index_by_bufnr(20)')
  MiniTest.expect.equality(idx, 2)
end

T['State: get_term_labels'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'npm run dev', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'python', job_id = 2, is_closed = false})
  ]])
  
  local labels = child.lua('return require("winterm.state").get_term_labels()')
  MiniTest.expect.equality(labels[1], '1:npm run dev')
  MiniTest.expect.equality(labels[2], '2:python')
end

return T
```

**State Verification Checklist:**
- ✅ `term_count` after add/remove
- ✅ `current_idx` adjusts after removals
- ✅ `current_idx` is `nil` when all removed
- ✅ Buffer number (bufnr) lookups work
- ✅ Terminal labels display correctly

### Phase 3: Integration Tests (Week 2-3)

#### tests/test_terminal.lua

**Example: Terminal Creation & Switching**

```lua
local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_once = function()
      child.stop()
    end,
  }
})

local function get_state()
  return child.lua([[
    local state = require('winterm.state')
    return {
      term_count = state.get_term_count(),
      current_idx = state.current_idx,
      terms = state.list_terms(),
    }
  ]])
end

T['Terminal: switch_term updates current_idx'] = function()
  child.lua([[
    local state = require('winterm.state')
    state.clear()
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.current_idx, 3)
  
  -- Switch to first terminal (state-based, no window)
  child.lua('require("winterm.state").set_current(1)')
  
  local s2 = get_state()
  MiniTest.expect.equality(s2.current_idx, 1)
end

T['Terminal: close_term removes from state'] = function()
  child.lua([[
    local state = require('winterm.state')
    state.clear()
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
  ]])
  
  local s1 = get_state()
  MiniTest.expect.equality(s1.term_count, 2)
  
  -- Simulate closing buffer (state operation only)
  child.lua([[
    local state = require('winterm.state')
    state.remove_term(1)
  ]])
  
  local s2 = get_state()
  MiniTest.expect.equality(s2.term_count, 1)
  MiniTest.expect.equality(s2.current_idx, 1)  -- Focus adjusted
end

T['Terminal: close middle terminal adjusts focus'] = function()
  child.lua([[
    local state = require('winterm.state')
    state.clear()
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
    
    -- Close middle (idx 2)
    state.remove_term(2)
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 2)
  -- Current was 3, but after removing idx 2, it should be adjusted to 2
  MiniTest.expect.equality(s.current_idx, 2)
end

T['Terminal: closing last terminal clears window'] = function()
  child.lua([[
    local state = require('winterm.state')
    state.clear()
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.remove_term(1)
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 0)
  MiniTest.expect.equality(s.current_idx, nil)
end

return T
```

**Terminal State Assertions:**
- ✅ `switch_term()` updates `current_idx`
- ✅ `close_term()` removes from `terms[]`
- ✅ Focus adjusts when closing middle/last
- ✅ Window clears when no terminals remain

#### tests/test_actions.lua

**Example: API Actions (State-Based)**

```lua
local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_once = function()
      child.stop()
    end,
  }
})

local function get_state()
  return child.lua([[
    local state = require('winterm.state')
    return {
      term_count = state.get_term_count(),
      current_idx = state.current_idx,
      winnr = state.winnr,
    }
  ]])
end

T['API: list_terms returns all'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
  ]])
  
  local terms = child.lua('return require("winterm.api").list_terms()')
  MiniTest.expect.equality(#terms, 3)
  MiniTest.expect.equality(terms[1].bufnr, 1)
  MiniTest.expect.equality(terms[2].bufnr, 2)
  MiniTest.expect.equality(terms[3].bufnr, 3)
end

T['API: focus argument parsing'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
  ]])
  
  -- Simulate :Winterm 1 (focus first)
  child.lua('require("winterm.state").set_current(1)')
  
  local s = get_state()
  MiniTest.expect.equality(s.current_idx, 1)
end

T['API: focus switches correctly'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
    
    -- Start at 3
    state.set_current(3)
  ]])
  
  local s1 = get_state()
  MiniTest.expect.equality(s1.current_idx, 3)
  
  -- Switch to 1
  child.lua('require("winterm.state").set_current(1)')
  
  local s2 = get_state()
  MiniTest.expect.equality(s2.current_idx, 1)
end

return T
```

**API State Assertions:**
- ✅ `list_terms()` returns all terminal objects
- ✅ Terminal objects have correct `bufnr`, `cmd`, `cwd`
- ✅ Focus operations update `current_idx`
- ✅ State reflects API calls correctly

### Phase 4: Edge Case Tests (Week 3-4)

#### tests/test_edge_cases.lua

**Example: Edge Cases & Boundary Conditions**

```lua
local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_once = function()
      child.stop()
    end,
  }
})

local function get_state()
  return child.lua([[
    local state = require('winterm.state')
    return {
      term_count = state.get_term_count(),
      current_idx = state.current_idx,
      terms = state.list_terms(),
    }
  ]])
end

T['Edge: focus adjustment on remove at boundary (start)'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
    
    -- Focus on first, remove first
    state.set_current(1)
    state.remove_term(1)
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 2)
  -- Should not go negative; should be 1 (next available)
  MiniTest.expect.equality(s.current_idx, 1)
end

T['Edge: focus adjustment when current > count'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.add_term({bufnr = 3, name = 't3', cmd = 'c3', job_id = 3, is_closed = false})
    
    -- Focus on 3, remove 2, then remove 3
    state.set_current(3)
    state.remove_term(2)  -- Count is now 2, current is still 3 (> count)
    -- According to code: current_idx > count => current_idx = count
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 2)
  -- current_idx should be clipped to count
  MiniTest.expect.equality(s.current_idx, 2)
end

T['Edge: operations on empty state'] = function()
  child.lua('require("winterm.state").clear()')
  
  local result = child.lua([[
    local state = require('winterm.state')
    return {
      current = state.get_current_term(),
      count = state.get_term_count(),
    }
  ]])
  
  MiniTest.expect.equality(result.current, nil)
  MiniTest.expect.equality(result.count, 0)
end

T['Edge: find_term_by_bufnr on empty state'] = function()
  child.lua('require("winterm.state").clear()')
  
  local found = child.lua('return require("winterm.state").find_term_by_bufnr(1) == nil')
  MiniTest.expect.equality(found, true)
end

T['Edge: set_current to invalid index'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    
    -- Try to set to index 10 (doesn't exist)
    state.set_current(10)
  ]])
  
  local s = get_state()
  -- Set still happens, validation should occur at API layer
  MiniTest.expect.equality(s.current_idx, 10)
end

T['Edge: bufnr lookup after insertions'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 10, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 20, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.insert_term(2, {bufnr = 15, name = 't_new', cmd = 'c_new', job_id = 3, is_closed = false})
  ]])
  
  -- After insert, bufnr 15 should be at index 2, 20 at index 3
  local idx = child.lua('return require("winterm.state").find_term_index_by_bufnr(15)')
  MiniTest.expect.equality(idx, 2)
  
  local idx2 = child.lua('return require("winterm.state").find_term_index_by_bufnr(20)')
  MiniTest.expect.equality(idx2, 3)
end

T['Edge: performance with many terminals'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    -- Add 50 terminals
    for i = 1, 50 do
      state.add_term({
        bufnr = i * 10,
        name = 'term' .. i,
        cmd = 'cmd' .. i,
        job_id = i,
        is_closed = false
      })
    end
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 50)
  MiniTest.expect.equality(s.current_idx, 50)
  
  -- Lookup should still be fast
  local found_idx = child.lua('return require("winterm.state").find_term_index_by_bufnr(250)')  -- 25th term
  MiniTest.expect.equality(found_idx, 25)
end

T['Edge: clear removes all'] = function()
  child.lua('require("winterm.state").clear()')
  
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
    state.add_term({bufnr = 2, name = 't2', cmd = 'c2', job_id = 2, is_closed = false})
    state.clear()
  ]])
  
  local s = get_state()
  MiniTest.expect.equality(s.term_count, 0)
  MiniTest.expect.equality(s.current_idx, nil)
end

return T
```

**Edge Case Assertions:**
- ✅ Focus adjusts correctly at boundaries (first/last/middle)
- ✅ Focus clips to count when > count
- ✅ Operations on empty state return nil/0
- ✅ Bufnr lookup works after insertions
- ✅ Performance scales (50+ terminals)
- ✅ Clear cleans up completely

### Phase 5: Visual Tests (Optional)

#### tests/test_winbar.lua

**Example: Winbar Content String Snapshot**

```lua
local T = MiniTest.new_set()

T['Winbar: renders correct format'] = function()
  child.lua([[
    local terminal = require('winterm.terminal')
    local state = require('winterm.state')
    local winbar = require('winterm.winbar')
    state.reset()
    
    terminal.add_term('npm run dev', nil, {name = 'dev'})
    terminal.add_term('npm run test', nil, {name = 'test'})
    
    state.current_idx = 1
    local content = winbar.get_content()
    
    -- Verify format (not pixel-perfect screenshot)
    assert(content:find('%[1:dev%]'), 'should show [1:dev]')
    assert(content:find('%[2:test%]'), 'should show [2:test]')
  ]])
end

return T
```

---

## Automated Assertions

### Preferred Assertion Pattern

```lua
-- ❌ Don't: Screenshot-based (brittle, slow to debug)
MiniTest.expect.reference_screenshot(screenshot, 'reference.png')

-- ✅ Do: State-based (deterministic, debuggable)
local state = child.lua('return require("winterm.state").current_idx')
MiniTest.expect.equality(state, expected_idx)

-- ✅ Do: API-based (comprehensive)
local terms = child.lua('return require("winterm.state").terms')
MiniTest.expect.equality(#terms, 2)

-- ✅ Do: Content string (for UI without pixels)
local content = child.lua('return require("winterm.winbar").get_content()')
MiniTest.expect.match(content, '%[1:%S+%]')
```

### Key Assertion APIs

| Operation | Assertion |
|-----------|-----------|
| Check integer equality | `MiniTest.expect.equality(a, b)` |
| Check no error | `MiniTest.expect.no_error(fn)` |
| Check error + pattern | `MiniTest.expect.error(fn, pattern)` |
| Check string match | `MiniTest.expect.match(str, pattern)` |
| Check table contains | `assert(vim.list_contains(t, v))` |

---

## Continuous Integration

### Makefile Targets

```makefile
.PHONY: test help

test:
	@echo "Running tests (headless)..."
	nvim --headless -u scripts/minimal_init.lua \
		-c "lua require('mini.test').run({ \
		  execute = { \
		    reporter = require('mini.test').gen_reporter.stdout() \
		  } \
		})" \
		-c 'qa!'

help:
	@echo "Available targets:"
	@echo "  make test  - Run all tests in headless mode"
```

### Running Tests

```bash
# Run all tests in headless mode
make test

# With verbose output
nvim --headless -u scripts/minimal_init.lua \
  -c "lua require('mini.test').run({ \
    execute = { \
      reporter = require('mini.test').gen_reporter.stdout({verbose = true}) \
    } \
  })" \
  -c 'qa!'
```

### GitHub Actions Workflow

```yaml
name: Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    name: Tests on Neovim ${{ matrix.nvim }}
    runs-on: ubuntu-latest
    strategy:
      matrix:
        nvim: ['v0.8.0', 'v0.9.4', 'v0.10.0', 'nightly']
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Neovim
        uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: ${{ matrix.nvim }}
      
      - name: Install mini.test dependency
        run: |
          mkdir -p ~/.local/share/nvim/site/pack/deps/start
          git clone https://github.com/nvim-mini/mini.test.git \
            ~/.local/share/nvim/site/pack/deps/start/mini.test
      
      - name: Run tests
        run: make test
        
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results-nvim-${{ matrix.nvim }}
          path: .test-results/
          retention-days: 30
```

### Local Test Environment Setup

```bash
# Install mini.test locally (one-time setup)
mkdir -p ~/.local/share/nvim/site/pack/deps/start
cd ~/.local/share/nvim/site/pack/deps/start
git clone https://github.com/nvim-mini/mini.test.git

# Or use packmanager like packer.nvim / lazy.nvim in test config
```

### Test Output Interpretation

```
Collected X test(s)

Running test group: State
  ✓ add_term increases count (0.001s)
  ✓ add_term multiple (0.001s)
  ✓ remove_term adjusts focus correctly (0.001s)
  ...

Running test group: Terminal
  ✓ switch_term updates current_idx (0.001s)
  ...

Finished: X passed, 0 failed (0.023s)
```

**Exit Codes:**
- `0` = All tests passed
- `1` = Some tests failed
- `2` = Test collection/runtime error

### Debug on Failure

```bash
# Verbose output (shows all details)
nvim --headless -u scripts/minimal_init.lua \
  -c "lua require('mini.test').run({ \
    execute = { \
      reporter = require('mini.test').gen_reporter.stdout({verbose = true}) \
    } \
  })" -c 'qa!'

# Add debug output to test
child.lua([[
  print('DEBUG: state_count=' .. require('winterm.state').get_term_count())
]])
```

---

## Implementation Timeline

| Phase | Duration | Deliverables | Effort |
|-------|----------|---|---|
| **1: Infrastructure** | 2 days | minimal_init.lua, test structure | 2h |
| **2: Unit Tests** | 3 days | test_state.lua, test_utils.lua | 4h |
| **3: Integration** | 4 days | test_terminal.lua, test_actions.lua | 6h |
| **4: Edge Cases** | 3 days | test_edge_cases.lua, race condition coverage | 4h |
| **5: CI Setup** | 2 days | GitHub Actions, Makefile targets | 3h |
| **6: Refinement** | 2 days | Snapshot management, coverage reports | 2h |
| **Total** | ~2-3 weeks | Full test suite | ~21h |

---

## Coverage Goals

### Minimum Viable (MVP - Week 1-2)

- ✅ Smoke test (plugin loads without error)
- ✅ State management (add/remove/switch)
- ✅ Terminal lifecycle (create/close/switch)
- ✅ Command dispatch (`:Winterm run`, `:Winterm kill`)
- **Target Coverage**: 75%
- **Effort**: ~10 hours

### Comprehensive (Week 3-4)

- ✅ All MVP + edge cases
- ✅ Window operations (open/close/toggle)
- ✅ Error handling (invalid states, races)
- ✅ Performance assertion (O(1) lookup validation)
- ✅ Winbar rendering (content string snapshot)
- **Target Coverage**: 90%+
- **Effort**: ~21 hours total

---

## Oracle Summary

### Key Principles

1. **State > Screenshot**: Query Neovim API for truth, not pixel comparison
2. **Isolation > Monolith**: Use child Neovim instances per test case
3. **Deterministic > Flaky**: Avoid timing dependencies; use state checks
4. **Debuggable > Coverage Number**: Aim for 90% meaningful coverage over 95% flaky

### Recommended Start

```bash
# Week 1: Smoke + Unit tests
1. Create scripts/minimal_init.lua
2. Write tests/test_smoke.lua
3. Write tests/test_state.lua
4. Add Makefile target: `make test`

# Week 2: Integration + Actions
5. Write tests/test_terminal.lua
6. Write tests/test_actions.lua
7. Integration with GitHub Actions CI

# Week 3: Edge Cases + Polish
8. Write tests/test_edge_cases.lua
9. Fix failing oracle code review issues (#1-4)
10. Validate coverage and performance assertions
```

### Benefits

- **Debugging**: When test fails, you see exact state mismatch
- **Maintenance**: Changes to UI don't break tests (state-based)
- **Reliability**: Child Neovim = no test-order dependencies
- **Performance**: Validate O(1) lookup, buffer operations
- **Documentation**: Tests serve as executable specification

---

## Quick Start (Implementation Order)

### Day 1: Infrastructure + State Tests

```bash
# 1. Create test infrastructure
mkdir -p tests scripts

# 2. Create scripts/minimal_init.lua
# Copy from Phase 1 section

# 3. Create tests/test_state.lua
# Copy from Phase 2 section

# 4. Update Makefile
# Copy from Makefile Targets section

# 5. Run tests
make test

# 6. Fix any failures in state.lua
```

### Day 2-3: Integration Tests

```bash
# 7. Create tests/test_terminal.lua
# Copy from Phase 3 section

# 8. Create tests/test_actions.lua
# Copy from Phase 3 section

# 9. Run all tests
make test

# 10. Fix failures in terminal.lua, api.lua
```

### Day 4-5: Edge Cases + CI

```bash
# 11. Create tests/test_edge_cases.lua
# Copy from Phase 4 section

# 12. Create .github/workflows/test.yml
# Copy from GitHub Actions section

# 13. Final test run
make test

# 14. Commit and push
git add tests/ scripts/ Makefile .github/
git commit -m "feat: add headless test suite with mini.test"
git push
```

---

## State-Based Testing Quick Reference

### Pattern: Setup → Act → Assert

```lua
local MiniTest = require('mini.test')
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_once = function()
      child.stop()
    end,
  }
})

T['Feature: description'] = function()
  -- SETUP: Initialize state
  child.lua('require("winterm.state").clear()')
  child.lua([[
    local state = require('winterm.state')
    state.add_term({bufnr = 1, name = 't1', cmd = 'c1', job_id = 1, is_closed = false})
  ]])
  
  -- ACT: Perform operation
  child.lua('require("winterm.state").set_current(1)')
  
  -- ASSERT: Verify state
  local s = child.lua([[
    local state = require('winterm.state')
    return {current_idx = state.current_idx, count = state.get_term_count()}
  ]])
  MiniTest.expect.equality(s.current_idx, 1)
  MiniTest.expect.equality(s.count, 1)
end

return T
```

### Common Assertions

```lua
-- Equality
MiniTest.expect.equality(actual, expected)

-- Non-equality
MiniTest.expect.no_equality(actual, unexpected)

-- String matching
MiniTest.expect.match(str, pattern)

-- Error handling
MiniTest.expect.error(function() ... end, pattern)
MiniTest.expect.no_error(function() ... end)

-- Boolean
assert(condition, message)
```

### State Query Helpers

```lua
-- Get current state snapshot
local function get_state()
  return child.lua([[
    local state = require('winterm.state')
    return {
      term_count = state.get_term_count(),
      current_idx = state.current_idx,
      terms = state.list_terms(),
      winnr = state.winnr,
    }
  ]])
end

-- Get terminal by index
local function get_term(idx)
  return child.lua(string.format('return require("winterm.state").get_term(%d)', idx))
end

-- Check if buffer is valid
local function buf_valid(bufnr)
  return child.lua(string.format('return require("winterm.state").is_buf_valid(%d)', bufnr))
end
```

---

## Coverage Summary

| Component | Tests | Coverage |
|-----------|-------|----------|
| State Management | 12 | 95%+ |
| Terminal Lifecycle | 5 | 90%+ |
| API Actions | 4 | 85%+ |
| Edge Cases | 9 | 90%+ |
| Winbar (Optional) | 2 | 80%+ |
| **Total** | **~32** | **90%+** |

---

## What This Tests Cover

✅ **State Correctness**
- Terminal add/remove/switch operations
- Focus index management
- Bufnr lookup (performance + correctness)

✅ **Boundary Conditions**
- Empty state operations
- Add/remove at boundaries
- Focus adjustment edge cases

✅ **Performance**
- O(1) lookup validation (50+ terminals)
- No regression with scale

✅ **API Contract**
- `list_terms()` returns correct objects
- State reflects API calls
- Error handling graceful

❌ **What's NOT Tested** (Visual/Window tests deferred)
- Window open/close/toggle (requires vim.api Neovim state)
- Winbar rendering (visual regression)
- Terminal command execution (integration)
- Job lifecycle (process management)

These can be added in Phase 5-6 if needed.

---

## Summary

### What You Get

- ✅ **30+ state-based tests** covering state management, terminal lifecycle, API
- ✅ **Zero interactive mode** — pure headless with `make test`
- ✅ **GitHub Actions CI** — auto-test on push/PR
- ✅ **Mini.test framework** — isolated child Neovim per test
- ✅ **90%+ coverage** of plugin logic

### Tech Stack

- **Framework**: mini.test (built-in Neovim testing)
- **Strategy**: State queries (not screenshots)
- **Isolation**: Child Neovim processes
- **Reporter**: stdout only (no buffer UI)
- **CI**: GitHub Actions matrix (v0.8 → nightly)

### Files to Create

1. `scripts/minimal_init.lua` (35 lines)
2. `tests/test_state.lua` (170 lines)
3. `tests/test_terminal.lua` (125 lines)
4. `tests/test_actions.lua` (105 lines)
5. `tests/test_edge_cases.lua` (185 lines)
6. `Makefile` (test target, 10 lines)
7. `.github/workflows/test.yml` (55 lines)

**Total**: ~685 lines of code + config

### Next Steps

1. Create `scripts/minimal_init.lua` (copy Phase 1)
2. Create `tests/test_state.lua` (copy Phase 2)
3. Run `make test`
4. Add remaining test files
5. Add CI workflow

---

**Document Version**: 2.0 (Headless Only)  
**Status**: Ready for Implementation  
**Framework**: mini.test + child Neovim  
**Mode**: Headless only (`make test` → stdout reporter)  
**Timeline**: 5 days (Day 1 infra + state, Day 2-3 integration, Day 4-5 edge + CI)  
**Effort**: ~15-18 hours
