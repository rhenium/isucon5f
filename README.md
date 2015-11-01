# ISUCON 5 final 最終ソースコード
チーム「にゃーん」の最終ソースコード一式です。Ruby + ngx_lua (OpenResty) + Redis です。

## ブログ
* [ISUCON 5 本選に出た - れにろぐ](https://rhe.jp/blog/2015/11/01/isucon-5/)

## このリポジトリに欠けているもの
* supervisord の設定ファイル
  * サーバー a のみ、webapp/ruby/looper.rb とソースからインストールした OpenResty を起動させるように
* Redis の設定ファイル
  * 0.0.0.0 で listen するように
