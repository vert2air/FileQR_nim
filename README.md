
Windows Only.


## wNimのリポジトリ

wNim のオリジナルは、nim 2.2 だとエラーになってしまう。
https://github.com/khchen/wNim
bug fix の Pull request が発行されていて、エラーが解決されている。
しかし、リポジトリがもうメンテナンスされていないようで、mergeされていない。
Pull requestの発行者のリポジトリを参照することにする。
ありがとう、retsyo!


## Build

```
git submodule init
git submodule update

cd fileQr
nim c --path=../_deps --app:gui fileQr.nim
```

