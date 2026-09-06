'use strict';
'require view';

return view.extend({
        render: function() {
                window.location = '/cgi-bin/traccar';
                return E([]);
        }
});