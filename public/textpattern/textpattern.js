/*
 * Textpattern on Rails -- core admin-side behaviours (no dependencies).
 */
(function () {
    'use strict';

    var txp = window.textpattern || {};
    var t = function (key) { return (txp.textarray && txp.textarray[key]) || key; };
    var store = {
        get: function (k) { try { return window.localStorage.getItem(k); } catch (e) { return null; } },
        set: function (k, v) { try { window.localStorage.setItem(k, v); } catch (e) { /* ignore */ } }
    };

    // Dark mode ("lightswitch"), remembered per browser.
    var applyTheme = function (mode) {
        if (mode === 'dark' || mode === 'light') {
            document.documentElement.setAttribute('data-theme', mode);
        } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
            document.documentElement.setAttribute('data-theme', 'dark');
        }
    };
    applyTheme(store.get('txp_lightswitch'));

    var ready = function (fn) {
        if (document.readyState !== 'loading') { fn(); } else { document.addEventListener('DOMContentLoaded', fn); }
    };

    var on = function (selector, event, handler) {
        document.addEventListener(event, function (e) {
            var el = e.target.closest ? e.target.closest(selector) : null;
            if (el) { handler.call(el, e, el); }
        });
    };

    ready(function () {
        document.body.classList.remove('not-ready');

        // Mobile navigation toggle and dropdown menus, unless the admin theme
        // brings its own (Hive ships Bootstrap's jQuery dropdown/collapse).
        // (Checked on use: theme scripts may run after this one.)
        var themeNav = function () { return !!(window.jQuery && window.jQuery.fn && window.jQuery.fn.dropdown); };

        on('.txp-nav-toggle', 'click', function (e, btn) {
            if (themeNav()) { return; }
            var nav = document.getElementById(btn.getAttribute('aria-controls') || 'txp-nav');
            if (!nav) { return; }
            var open = nav.classList.toggle('in');
            btn.setAttribute('aria-expanded', open ? 'true' : 'false');
            btn.classList.toggle('collapsed', !open);
        });

        on('.txp-nav .dropdown-toggle', 'click', function (e, a) {
            if (themeNav()) { return; }
            e.preventDefault();
            var li = a.parentNode;
            var wasOpen = li.classList.contains('open');
            document.querySelectorAll('.txp-nav .dropdown.open').forEach(function (d) { d.classList.remove('open'); });
            if (!wasOpen) { li.classList.add('open'); }
        });

        document.addEventListener('click', function (e) {
            if (!themeNav() && !e.target.closest('.txp-nav .dropdown')) {
                document.querySelectorAll('.txp-nav .dropdown.open').forEach(function (d) { d.classList.remove('open'); });
            }
        });

        // Lightswitch.
        on('#lightswitch', 'click', function (e) {
            e.preventDefault();
            var dark = document.documentElement.getAttribute('data-theme') === 'dark';
            var mode = dark ? 'light' : 'dark';
            document.documentElement.setAttribute('data-theme', mode);
            store.set('txp_lightswitch', mode);
        });

        // Inline help: loads ?event=help&step=pophelp&item=... into a dialog
        // (a jQuery UI dialog, as in Textpattern, so admin themes style it).
        var showHelp = function (html) {
            if (window.jQuery && window.jQuery.fn.dialog) {
                var $ = window.jQuery;
                var $dialog = $('#pophelp_dialog');
                if (!$dialog.length) {
                    $dialog = $('<div id="pophelp_dialog"></div>').appendTo('body');
                    $dialog.dialog({
                        classes: { 'ui-dialog': 'txp-dialog-container' },
                        autoOpen: false,
                        width: 440,
                        title: t('help')
                    });
                }
                $dialog.dialog('close').html(html).dialog('open');
            } else {
                var box = document.getElementById('pophelp_dialog') || document.body.appendChild(document.createElement('dialog'));
                box.id = 'pophelp_dialog';
                box.innerHTML = html + '<form method="dialog"><button>' + t('close') + '</button></form>';
                box.showModal();
            }
        };

        on('.pophelp, .pophelpsubtle', 'click', function (e, a) {
            e.preventDefault();
            var cached = a.getAttribute('data-item');
            if (cached) {
                showHelp(decodeURIComponent(cached));
                return;
            }
            a.classList.add('busy');
            fetch(a.href, { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' } })
                .then(function (r) { return r.text(); })
                .then(function (html) {
                    a.setAttribute('data-item', encodeURIComponent(html));
                    showHelp(html);
                })
                .finally(function () { a.classList.remove('busy'); });
        });

        // Message pane.
        on('.messageflash .close', 'click', function (e, btn) {
            e.preventDefault();
            var flash = btn.closest('.messageflash');
            if (flash) { flash.remove(); }
        });
        document.querySelectorAll('.messageflash:not(.error):not(.warning)').forEach(function (flash) {
            setTimeout(function () { flash.style.transition = 'opacity .4s'; flash.style.opacity = '0'; setTimeout(function () { flash.remove(); }, 450); }, 7000);
        });

        // Auto-submitting selects.
        on('[data-submit-on="change"]', 'change', function (e, el) {
            if (el.form) { el.form.submit(); }
        });
        on('[data-submit-on="change-reload"]', 'change', function (e, el) {
            var url = new URL(window.location.href);
            url.searchParams.set(el.name, el.value);
            window.location.href = url.toString();
        });

        // Confirmations.
        on('[data-confirm]', 'click', function (e, el) {
            if (!window.confirm(el.getAttribute('data-confirm') || t('are_you_sure'))) {
                e.preventDefault();
                e.stopImmediatePropagation();
            }
        });

        // Multi-edit count ("With {count} selected…"); the method select is
        // disabled while nothing is selected, as in Textpattern.
        var updateMultiEdit = function (form) {
            if (!form) { return; }
            var count = form.querySelectorAll('input[name="selected[]"]:checked').length;
            form.querySelectorAll('select.multi-edit-method').forEach(function (sel) {
                var first = sel.querySelector('option[value=""]');
                var txt = sel.getAttribute('data-txt');
                if (first && txt) { first.textContent = txt.replace('{count}', count); }
                sel.disabled = !count;
                if (!count && sel.value) {
                    sel.value = '';
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                }
            });
        };
        document.querySelectorAll('select.multi-edit-method').forEach(function (sel) { updateMultiEdit(sel.form); });

        // Select-all checkboxes in lists.
        on('input[name="select_all"]', 'change', function (e, box) {
            var table = box.closest('table') || box.closest('form');
            table.querySelectorAll('input[name="selected[]"]').forEach(function (cb) {
                cb.checked = box.checked;
                var row = cb.closest('tr');
                if (row) { row.classList.toggle('selected', box.checked); }
            });
            updateMultiEdit(box.form);
        });
        on('input[name="selected[]"]', 'change', function (e, cb) {
            var row = cb.closest('tr');
            if (row) { row.classList.toggle('selected', cb.checked); }
            updateMultiEdit(cb.form);
        });

        // Multi-edit: show method-specific options and validate.
        on('select.multi-edit-method', 'change', function (e, sel) {
            var box = sel.closest('.multi-edit');
            box.querySelectorAll('.multi-option').forEach(function (opt) {
                var match = opt.getAttribute('data-for') === sel.value;
                opt.hidden = !match;
                opt.querySelectorAll('input, select, textarea').forEach(function (f) { f.disabled = !match; });
            });
        });
        document.querySelectorAll('.multi-edit .multi-option').forEach(function (opt) {
            opt.querySelectorAll('input, select, textarea').forEach(function (f) { f.disabled = true; });
        });
        on('.multi-edit-submit', 'click', function (e, btn) {
            var form = btn.form;
            var method = form.querySelector('select.multi-edit-method');
            var checked = form.querySelectorAll('input[name="selected[]"]:checked').length;
            if (!method || !method.value || !checked) { e.preventDefault(); return; }
            if (/delete|remove/.test(method.value) && !window.confirm(t('confirm_delete_popup'))) { e.preventDefault(); }
        });

        // Collapsible panes.
        on('.txp-summary a', 'click', function (e, a) {
            e.preventDefault();
            var h = a.parentNode;
            var expanded = h.classList.toggle('expanded');
            a.setAttribute('aria-pressed', expanded ? 'true' : 'false');
            store.set('txp_pane_' + (a.getAttribute('aria-controls') || ''), expanded ? '1' : '0');
        });
        document.querySelectorAll('.txp-summary a[aria-controls]').forEach(function (a) {
            var state = store.get('txp_pane_' + a.getAttribute('aria-controls'));
            if (state === '0') { a.parentNode.classList.remove('expanded'); a.setAttribute('aria-pressed', 'false'); }
        });

        // Tab key inserts a tab in code editors.
        on('textarea.code, textarea.txp-template-code', 'keydown', function (e, ta) {
            if (e.key !== 'Tab' || e.shiftKey || e.ctrlKey || e.altKey || e.metaKey) { return; }
            e.preventDefault();
            var s = ta.selectionStart, end = ta.selectionEnd;
            ta.value = ta.value.substring(0, s) + '    ' + ta.value.substring(end);
            ta.selectionStart = ta.selectionEnd = s + 4;
            ta.dispatchEvent(new Event('input', { bubbles: true }));
        });

        // Ctrl/Cmd+S saves the current edit form.
        document.addEventListener('keydown', function (e) {
            if ((e.ctrlKey || e.metaKey) && e.key === 's') {
                var form = document.querySelector('form.txp-edit, form#article_form');
                var submit = form && form.querySelector('input.publish[type="submit"], button.publish');
                if (submit) { e.preventDefault(); submit.click(); }
            }
        });

        // Unsaved changes warning.
        document.querySelectorAll('form[data-dirty-check]').forEach(function (form) {
            var dirty = false;
            form.addEventListener('input', function () { dirty = true; });
            form.addEventListener('submit', function () { dirty = false; });
            window.addEventListener('beforeunload', function (e) {
                if (dirty) { e.preventDefault(); e.returnValue = ''; }
            });
        });

        // Show password.
        on('#show_password', 'change', function (e, cb) {
            document.querySelectorAll('.txp-maskable').forEach(function (input) { input.type = cb.checked ? 'text' : 'password'; });
        });

        // Write panel: Text / HTML / Preview views of body and excerpt.
        on('.txp-textarea-options a', 'click', function (e, a) {
            e.preventDefault();
            var field = a.getAttribute('data-field');
            var view = a.getAttribute('data-view');
            var textarea = document.getElementById(field);
            var preview = document.getElementById(field + '-preview');
            a.parentNode.querySelectorAll('a').forEach(function (x) { x.classList.toggle('active', x === a); });
            if (view === 'text') {
                textarea.hidden = false;
                preview.hidden = true;
                return;
            }
            var markup = document.querySelector('[name="textile_' + field + '"]');
            var body = new URLSearchParams();
            body.set('text', textarea.value);
            body.set('filter', markup ? markup.value : '1');
            fetch('/textpattern/preview', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-CSRF-Token': txp._txp_token },
                body: body.toString(),
                credentials: 'same-origin'
            }).then(function (r) { return r.text(); }).then(function (html) {
                textarea.hidden = true;
                preview.hidden = false;
                preview.classList.toggle('html-code', view === 'html');
                if (view === 'html') { preview.textContent = html; } else { preview.innerHTML = html; }
            });
        });

        // Article title → URL-only title suggestion.
        var title = document.getElementById('title');
        var urlTitle = document.getElementById('url-title');
        if (title && urlTitle && !urlTitle.value) {
            title.addEventListener('input', function () {
                if (urlTitle.getAttribute('data-touched')) { return; }
                urlTitle.placeholder = title.value.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
                    .replace(/[^a-z0-9\s-]/g, '').trim().replace(/[\s-]+/g, '-');
            });
            urlTitle.addEventListener('input', function () { urlTitle.setAttribute('data-touched', '1'); });
        }

        // Copy buttons (Diagnostics).
        on('[data-copy-from]', 'click', function (e, btn) {
            var source = document.getElementById(btn.getAttribute('data-copy-from'));
            if (!source || !navigator.clipboard) { return; }
            navigator.clipboard.writeText(source.value || source.textContent);
            btn.lastChild.textContent = ' ' + t('copied');
        });

        // Tag builder: insert generated tag into the opener's editor.
        on('[data-insert-tag]', 'click', function (e, btn) {
            var code = document.getElementById('tag-result');
            if (!code) { return; }
            if (navigator.clipboard) { navigator.clipboard.writeText(code.value); }
            btn.textContent = t('copied');
        });

        // Delete buttons in edit panes.
        on('[data-delete-url]', 'click', function (e, btn) {
            e.preventDefault();
            if (!window.confirm(t('confirm_delete_popup'))) { return; }
            var form = document.createElement('form');
            form.method = 'post';
            form.action = btn.getAttribute('data-delete-url');
            var tok = document.createElement('input');
            tok.type = 'hidden';
            tok.name = 'authenticity_token';
            tok.value = txp._txp_token;
            form.appendChild(tok);
            document.body.appendChild(form);
            form.submit();
        });
    });
})();
