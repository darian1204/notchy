# Rutas y datos que comparten los scripts. Se carga con `source`, no se ejecuta.
RAIZ=${0:A:h:h}
DERIVADOS=$RAIZ/build/DerivedData
REGISTROS=$RAIZ/build/logs
APP=$DERIVADOS/Build/Products/Debug/Isla.app
mkdir -p $REGISTROS

# Lee un ajuste de Config/Base.xcconfig, que es la única fuente del identificador y del equipo.
ajuste() {
    sed -nE "s/^$1[[:space:]]*=[[:space:]]*(.*)$/\1/p" $RAIZ/Config/Base.xcconfig
}

# compilar_app [ajustes de xcodebuild…]: deja el registro en build/logs/app.log.
compilar_app() {
    xcodebuild -project $RAIZ/Isla.xcodeproj -scheme Isla -configuration Debug \
        -derivedDataPath $DERIVADOS -allowProvisioningUpdates build "$@" > $REGISTROS/app.log 2>&1
}
