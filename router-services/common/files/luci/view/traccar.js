'require view';

return view.extend({
	render: function() {
		// HTTPS-страницу нельзя грузить по HTTP (mixed content)
		var url = (window.location.protocol === 'https:')
			? 'https://himik1987.duckdns.org:8445/'
			: 'http://192.168.1.1:8082/';

		return E('div', {}, [
			E('div', { 'style': 'display:flex;gap:10px;align-items:center;margin-bottom:10px' }, [
				E('a', {
					'href': url,
					'target': '_blank',
					'rel': 'noopener',
					'class': 'btn cbi-button cbi-button-apply'
				}, 'Открыть Traccar в новой вкладке'),
				E('span', { 'style': 'color:#8b98b3;font-size:12px' }, url)
			]),
			E('iframe', {
				'src': url,
				'style': 'width:100%;height:calc(100vh - 250px);min-height:520px;border:0;border-radius:10px;background:#0f1420'
			})
		]);
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
