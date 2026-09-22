qml_module(caelestia-internal
    URI Caelestia.Internal
    INCLUDE_PREFIX internal
    SOURCES
        niriipc.hpp niriipc.cpp
        nirisocket.hpp nirisocket.cpp
    LIBRARIES
        Qt::Gui
        Qt::Quick
        Qt::Concurrent
        Qt::Network
        caelestia-config
    DEPENDENCIES
        Caelestia.Config
)
