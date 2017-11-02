xquery version "3.0";

module namespace tumblr="http://history.state.gov/ns/xquery/tumblr";

declare variable $tumblr:api-base-url := 'http://api.tumblr.com/v2';

declare function tumblr:send-request(
        $http-method as xs:string, 
        $api-url as xs:string
        ) {
    let $request := <http:request href="{$api-url}" method="{$http-method}" http-version="1.1"/>
    let $response := http:send-request($request)
    return 
        (
        $request, 
        $response
        )
};

declare function tumblr:blog-info(
        $consumer-key as xs:string, 
        $base-hostname as xs:string
        ) {
    let $http-method := 'GET'
    let $api-method := concat('blog/', $base-hostname, '/info')
    let $query-string := 
        concat('api_key=', $consumer-key)
    let $api-url := concat($tumblr:api-base-url, '/', $api-method, '?', $query-string)
    return 
        tumblr:send-request($http-method, $api-url)
};

declare function tumblr:blog-posts(
        $consumer-key as xs:string, 
        $base-hostname as xs:string, 
        $type as xs:string?, 
        $id as xs:integer?,
        $tag as xs:string?, 
        $limit as xs:integer?,
        $offset as xs:integer?,
        $reblog-info as xs:boolean?,
        $notes-info as xs:boolean?,
        $filter as xs:string?
        ) {
    let $http-method := 'GET'
    let $api-method := concat('blog/', $base-hostname, '/posts')
    let $query-string := 
        string-join(
            (
            if ($type) then concat('type=', $type) else (),
            if ($id) then concat('id=', $id) else (),
            if ($tag) then concat('tag=', $tag) else (),
            if ($limit) then concat('limit=', $limit) else (),
            if ($offset) then concat('offset=', $offset) else (),
            if ($reblog-info) then concat('reblog-info=', $reblog-info) else (),
            if ($notes-info) then concat('notes-info=', $notes-info) else (),
            if ($filter) then concat('filter=', $filter) else (),
            concat('api_key=', $consumer-key)
            ),
            '&amp;'
        )
    let $api-url := concat($tumblr:api-base-url, '/', $api-method, '?', $query-string)
    return 
        tumblr:send-request($http-method, $api-url)
};