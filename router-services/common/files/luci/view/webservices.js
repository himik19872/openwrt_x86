'require view';

return view.extend({
	render: function() {
		var base = 'http://192.168.1.1';

		var cards = [
			{
				title: 'Home Assistant',
				desc: 'Умный дом · ho.himik1987.duckdns.org',
				url: 'http://192.168.1.30:8123/',
				ext: 'https://ho.himik1987.duckdns.org/'
			},
			{
				title: 'Traccar',
				desc: 'GPS-трекинг · traccar.himik1987.duckdns.org',
				url: base + ':8082/',
				ext: 'https://traccar.himik1987.duckdns.org/'
			},
			{
				title: 'NVR',
				desc: 'Видеонаблюдение · himik1987.duckdns.org',
				url: 'https://192.168.1.51/',
				ext: 'https://himik1987.duckdns.org/'
			},
			{
				title: 'Камера',
				desc: 'OpenIPC · video.himik1987.duckdns.org',
				url: 'http://192.168.1.61/',
				ext: 'https://video.himik1987.duckdns.org/'
			},
			{
				title: 'Домены и доступ',
				desc: 'Поддомены · DuckDNS · сертификат',
				url: '/cgi-bin/dnsui'
			},

			{
				title: 'ИБП — мониторинг',
				desc: 'NUT, заряд и события',
				url: '/cgi-bin/upsadmin?action=ui'
			},
			{
				title: 'Уведомления',
				desc: 'Telegram и устройства сети',
				url: '/cgi-bin/netmon?action=ui'
			},
			{
				title: 'LuCI',
				desc: 'Веб-интерфейс роутера',
				url: '/cgi-bin/luci'
			}
		];

		var cardStyle = [
			'background:rgba(127,127,127,0.08)',
			'border:1px solid rgba(127,127,127,0.25)',
			'border-radius:12px',
			'padding:16px 18px',
			'display:flex',
			'flex-direction:column',
			'gap:10px',
			'min-height:130px'
		].join(';');

		return E('div', {
			'style': 'display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px;margin-top:6px'
		}, cards.map(function(c) {
			var buttons = [
				E('a', {
					'href': c.url,
					'target': '_blank',
					'rel': 'noopener',
					'class': 'btn cbi-button cbi-button-apply'
				}, 'Открыть')
			];
			if (c.ext) {
				buttons.push(E('a', {
					'href': c.ext,
					'target': '_blank',
					'rel': 'noopener',
					'class': 'btn cbi-button'
				}, 'Из интернета'));
			}

			return E('div', { 'style': cardStyle }, [
				E('div', { 'style': 'font-weight:600;font-size:16px' }, c.title),
				E('div', { 'style': 'color:rgba(127,127,127,1);font-size:12px;flex:1' }, c.desc),
				E('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap' }, buttons)
			]);
		}));
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
