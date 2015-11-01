if not ngx.var.cookie_user_id then
    ngx.redirect("/login")
end

local email = ngx.var.cookie_email

ngx.print([[
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1">
<!-- The above 3 meta tags *must* come first in the head; any other head content must come *after* these tags -->

<title>AirISU</title>
<link href="/css/bootstrap.min.css" rel="stylesheet">
<link href="/css/jumbotron-narrow.css" rel="stylesheet">
</head>

<body>
<div class="container">
  <div class="header clearfix">
    <nav>
    <ul class="nav nav-pills pull-right">
      <li role="presentation" class="active"><a href="#">Home</a></li>
      <li role="presentation"><a href="/modify">設定</a></li>
      <li role="presentation" id="cancel-service-button"><a href="#">解約</a></li>
    </ul>
    </nav>
    <h3 class="text-muted">AirISU: ]])

ngx.print(ngx.unescape_uri(email))

ngx.print([[
</h3>
  </div>

  <div id="api-response-container">
  </div>

  <footer class="footer">
  <p>&copy; ISU Company 2015</p>
  </footer>

</div>

<div class="modal fade" id="CancelModal" style="display: none;">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
        <h4 class="modal-title">AirISU 解約</h4>
      </div>
      <div class="modal-body">
        <p>本当にサービスを解約しますか？</p>
      </div>
      <div class="modal-footer">
        <form method="POST" action="/cancel">
          <button type="submit" class="btn btn-danger">解約</button>
        </form>
      </div>
    </div>
  </div>
</div>

<div id="api-result-template-container" style="display:none;">
  <div class="row marketing api-result">
    <div class="col-lg-12">
      <h4></h4>
      <p></p>
    </div>
  </div>
</div>

<script src="/js/jquery-1.11.3.js"></script>
<script src="/js/bootstrap.js"></script>
<script src="/user.js"></script>
<script src="/js/airisu.js"></script>
<script>
$(function(){
  $('#cancel-service-button').click(function(){ $('#CancelModal').modal(); });
});
</script>
</body>
</html>]])
