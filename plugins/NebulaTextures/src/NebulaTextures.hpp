/*
 * Nebula Textures plug-in for Stellarium
 *
 * Copyright (C) 2024-2025 WANG Siliang
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef NEBULATEXTURES_HPP
#define NEBULATEXTURES_HPP


#include "StelModule.hpp"
#include <QJsonArray>
#include <QJsonObject>
#include <QHash>

class NebulaTexturesDialog;

class NebulaTextures : public StelModule
{
	Q_OBJECT
	Q_PROPERTY(bool flagShow            READ getShow              WRITE setShow           NOTIFY showChanged)

public:
	NebulaTextures();
	~NebulaTextures() override;

	// Methods defined in the StelModule class
	void init() override;

	// Activate only if update() does something.
	//void update(double deltaTime) override {}

	void draw(StelCore* core) override;

	double getCallOrder(StelModuleActionName actionName) const override;

	bool configureGui(bool show=true) override;

	QJsonObject getTextureStatus() const;
	QJsonArray listTextures() const;
	QJsonObject validateTexture(const QString& imageUrl) const;
	bool refreshCustomTextures(QString* error = Q_NULLPTR);
	bool gotoTexture(const QString& imageUrl, QString* error = Q_NULLPTR) const;
	bool removeTexture(const QString& imageUrl, QString* error = Q_NULLPTR);
	QJsonObject importTexture(const QJsonObject& request);
	bool getAvoidAreaConflict() const;
	void setAvoidAreaConflict(bool enabled);

public slots:
	bool getShow() const;

	void setShow(bool b);
	void handleCollectionLoaded();

signals:
	void showChanged(bool b);

private:
	NebulaTexturesDialog* configDialog;
	QString customConfigPath() const;
	QJsonObject textureItemStatus(const QJsonObject& tile) const;
	mutable QHash<QString, QJsonObject> imageValidationCache;
	mutable quint64 imageDecodeCount = 0;
	quint64 layerRebuildCount = 0;
};


#include <QObject>
#include "StelPluginInterface.hpp"

//! This class is used by Qt to manage a plug-in interface
class NebulaTexturesStelPluginInterface : public QObject, public StelPluginInterface
{
	Q_OBJECT
	Q_PLUGIN_METADATA(IID StelPluginInterface_iid)
	Q_INTERFACES(StelPluginInterface)
public:
	StelModule* getStelModule() const override;
	StelPluginInfo getPluginInfo() const override;
	QObjectList getExtensionList() const override { return QObjectList(); }
};

#endif /* NEBULATEXTURES_HPP */
