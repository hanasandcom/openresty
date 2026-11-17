import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const html = readFileSync(process.env.ERROR_TEMPLATE || new URL('../nginx/errors/error.html', import.meta.url), 'utf8');
const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
function errorPage(query = '?code=502') {
    let now = 0;
    let nextId = 1;
    const timers = new Map();
    const elements = new Map();
    const navigations = [];
    const element = id => {
        if (!elements.has(id)) elements.set(id, { textContent: '', remove() { this.removed = true; } });
        return elements.get(id);
    };
    const timer = (callback, delay, repeat) => {
        const id = nextId++;
        timers.set(id, { callback, delay, repeat, at: now + delay });
        return id;
    };
    const url = new URL('https://cdn.hanasand.com/library' + query);
    vm.runInNewContext(script, {
        URL, URLSearchParams,
        Date: class extends Date { static now() { return now; } },
        document: { getElementById: element, querySelector: element },
        window: {
            location: { href: url.href, search: url.search, hostname: url.hostname, assign: value => navigations.push(value) },
            setInterval: (fn, delay) => timer(fn, delay, true),
            setTimeout: (fn, delay) => timer(fn, delay, false),
            clearInterval: id => timers.delete(id),
        },
    });
    return {
        get message() { return element('retry-message').textContent; },
        get removed() { return element('retry-message').removed; },
        navigations, timers,
        tick(elapsed) {
            // One delayed callback models a tab resuming after timer throttling.
            now += elapsed;
            for (const [id, task] of [...timers]) {
                if (task.at > now) continue;
                if (task.repeat) task.at = now + task.delay;
                else timers.delete(id);
                task.callback();
            }
        },
    };
}

for (const [retry, seconds] of [5, 10, 20, 40, 80].entries()) {
    test(`attempt ${retry + 1} counts down from ${seconds}s and retries once`, () => {
        const page = errorPage(`?code=502&retries=${retry}&album=keep`);
        assert.equal(page.message, `Retrying in ${seconds}s. Attempt ${retry + 1} of 5.`);
        page.tick(1000);
        assert.equal(page.message, `Retrying in ${seconds - 1}s. Attempt ${retry + 1} of 5.`);
        page.tick(1000);
        assert.equal(page.message, `Retrying in ${seconds - 2}s. Attempt ${retry + 1} of 5.`);
        assert.equal(page.navigations.length, 0);
        page.tick((seconds - 2) * 1000);
        assert.equal(page.message, 'Retrying now…');
        assert.equal(page.navigations.length, 1);
        const next = new URL(page.navigations[0]);
        assert.equal(next.pathname, '/library');
        assert.equal(next.searchParams.get('album'), 'keep');
        assert.equal(next.searchParams.get('retries'), String(retry + 1));
        page.tick(100000);
        assert.equal(page.navigations.length, 1);
        assert.equal(page.timers.size, 0);
    });
}
test('a suspended tab catches up to elapsed time', () => {
    const page = errorPage('?code=503&retries=4');
    page.tick(37000);
    assert.equal(page.message, 'Retrying in 43s. Attempt 5 of 5.');
    page.tick(45000);
    assert.equal(page.navigations.length, 1);
});
test('retry limit stops automatic navigation', () => {
    for (const retries of ['5', '999']) {
        const page = errorPage(`?code=502&retries=${retries}`);
        assert.equal(page.message, 'Automatic retries stopped. Try again later.');
        assert.equal(page.timers.size, 0);
    }
});
test('invalid and negative retry counts cannot cause rapid or fractional attempts', () => {
    for (const retries of ['-5', '-Infinity', 'Infinity', 'bad', 'NaN', '0.5']) {
        const page = errorPage(`?code=502&retries=${retries}`);
        assert.equal(page.message, 'Retrying in 5s. Attempt 1 of 5.');
        page.tick(1000);
        assert.equal(page.navigations.length, 0);
    }
});
test('non-retryable errors do not schedule a countdown', () => {
    const page = errorPage('?code=404');
    assert.equal(page.removed, true);
    assert.equal(page.timers.size, 0);
});
