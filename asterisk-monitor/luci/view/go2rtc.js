'use strict';
'require view';

return view.extend({
        render: function() {
                window.location = '/cgi-bin/go2rtc';
                return E([]);
        }
});