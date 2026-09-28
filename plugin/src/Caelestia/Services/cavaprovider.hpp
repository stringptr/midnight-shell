#pragma once

#include <qqmlintegration.h>

#include <cava/cavacore.h>

#include "audioprovider.hpp"

namespace caelestia::services {

class CavaProcessor : public AudioProcessor {
    Q_OBJECT

public:
    explicit CavaProcessor(QObject* parent = nullptr);
    ~CavaProcessor() override;

    void setBars(int bars);

signals:
    void valuesChanged(QVector<double> values);

protected:
    void process() override;

private:
    struct cava_plan* m_plan;
    double* m_in;
    double* m_out;

    int m_bars;
    QVector<double> m_values;

    void reload();
    void initCava();
    void cleanup();
};

class CavaProvider : public AudioProvider {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int bars READ bars WRITE setBars NOTIFY barsChanged)

    Q_PROPERTY(QVector<double> values READ values NOTIFY valuesChanged)

    Q_PROPERTY(QString targetNodeName READ targetNodeName WRITE setTargetNodeName NOTIFY targetNodeNameChanged)

public:
    explicit CavaProvider(QObject* parent = nullptr);

    [[nodiscard]] int bars() const;
    void setBars(int bars);

    [[nodiscard]] QVector<double> values() const;

    [[nodiscard]] QString targetNodeName() const;
    void setTargetNodeName(const QString& name);

signals:
    void barsChanged();
    void valuesChanged();
    void targetNodeNameChanged();

private:
    int m_bars;
    QVector<double> m_values;
    QString m_targetNodeName;

    void updateValues(const QVector<double>& values);
};

} // namespace caelestia::services
