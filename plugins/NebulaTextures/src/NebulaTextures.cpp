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

#include "StelProjector.hpp"
#include "StelApp.hpp"
#include "StelCore.hpp"
#include "StelModuleMgr.hpp"
#include "StelModule.hpp"
#include "StelGui.hpp"
#include "StelGuiItems.hpp"
#include "StelFileMgr.hpp"
#include "StelMovementMgr.hpp"
#include "StelUtils.hpp"

#include "NebulaTextures.hpp"
#include "NebulaTexturesDialog.hpp"
#include "SkyCoords.hpp"
#include "TextureConfigManager.hpp"
#include "TileManager.hpp"

#include <stdexcept>
#include <cmath>
#include <limits>
#include <QDebug>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSettings>
#include <QSaveFile>
#include <QUuid>
#include <QUrl>

namespace
{
const QString ConfigPrefix = QStringLiteral("NebulaTextures");
const QString PluginDirectory = QStringLiteral("/modules/NebulaTextures/");
const QString CustomConfigFile = QStringLiteral("/modules/NebulaTextures/custom_textures.json");
const QString CustomTextureName = QStringLiteral("Custom Textures");
const QString DefaultTextureName = QStringLiteral("Nebulae");

QString normalizedLocalImageName(const QString& imageUrl)
{
	const QString cleaned = QDir::cleanPath(imageUrl.trimmed());
	if (cleaned.isEmpty() || QDir::isAbsolutePath(cleaned) || cleaned == QStringLiteral("..") || cleaned.startsWith(QStringLiteral("../")))
		return QString();
	const QUrl url(cleaned);
	if (!url.scheme().isEmpty())
		return QString();
	return QFileInfo(cleaned).fileName() == cleaned ? cleaned : QString();
}

bool readCorners(const QJsonObject& tile, QJsonArray* corners, QString* error)
{
	const QJsonArray worldCoords = tile.value(QStringLiteral("worldCoords")).toArray();
	if (worldCoords.size() != 1 || !worldCoords.at(0).isArray())
	{
		if (error) *error = QStringLiteral("invalid_world_coords");
		return false;
	}
	const QJsonArray values = worldCoords.at(0).toArray();
	if (values.size() != 4)
	{
		if (error) *error = QStringLiteral("invalid_corner_count");
		return false;
	}
	for (const QJsonValue& value : values)
	{
		if (!value.isArray())
		{
			if (error) *error = QStringLiteral("invalid_corner");
			return false;
		}
		const QJsonArray point = value.toArray();
		if (point.size() != 2 || !point.at(0).isDouble() || !point.at(1).isDouble())
		{
			if (error) *error = QStringLiteral("invalid_corner");
			return false;
		}
		const double ra = point.at(0).toDouble();
		const double dec = point.at(1).toDouble();
		if (!std::isfinite(ra) || !std::isfinite(dec) || ra < 0.0 || ra > 360.0 || dec < -90.0 || dec > 90.0)
		{
			if (error) *error = QStringLiteral("corner_out_of_range");
			return false;
		}
	}
	if (corners) *corners = values;
	return true;
}

double normalizedDegrees(double value)
{
	value = std::fmod(value, 360.0);
	return value < 0.0 ? value + 360.0 : value;
}
}

// Returns a new instance of NebulaTextures module.
StelModule* NebulaTexturesStelPluginInterface::getStelModule() const
{
	return new NebulaTextures();
}

// Provides plugin information, including metadata like ID, authors, description, version, and license.
StelPluginInfo NebulaTexturesStelPluginInterface::getPluginInfo() const
{
	// Allow to load the resources when used as a static plugin
	Q_INIT_RESOURCE(NebulaTextures);

	StelPluginInfo info;
	info.id = "NebulaTextures";
	info.displayedName = N_("Nebula Textures");
	info.authors = "WANG Siliang";
	info.contact = "bd7jay@outlook.com";
	info.description = N_("This plugin can plate-solve and position astronomical images, adding them as custom deep-sky object textures for rendering.");
	info.version = NEBULATEXTURES_PLUGIN_VERSION;
	info.license = NEBULATEXTURES_PLUGIN_LICENSE;
	return info;
}

// Constructor for NebulaTextures module, initializes GUI and connects signals.
NebulaTextures::NebulaTextures()
{
	setObjectName("NebulaTextures");
	configDialog = new NebulaTexturesDialog();
	connect(StelApp::getInstance().getModule("StelSkyLayerMgr"),
			SIGNAL(collectionLoaded()),configDialog,SLOT(initializeRefreshIfNeeded()));
}

// Destructor for NebulaTextures, cleaning up resources if necessary.
NebulaTextures::~NebulaTextures()
{
	// delete configDialog; // Resources are cleaned up automatically by Qt
}

// Configures the GUI, displaying the settings dialog if 'show' is true.
bool NebulaTextures::configureGui(bool show)
{
	if (show)
		configDialog->setVisible(true);
	return true;
}

// Returns the call order for the "Draw" action, used to determine when the module should be drawn.
double NebulaTextures::getCallOrder(StelModuleActionName actionName) const
{
	if (actionName == StelModule::ActionDraw)
		return StelApp::getInstance().getModuleMgr().getModule("NebulaMgr")->getCallOrder(actionName) + 10.0;
	return 0;
}

// Initializes actions, UI elements, and toolbar button for the NebulaTextures module.
void NebulaTextures::init()
{
	// Create action for enable/disable & hook up signals
	addAction("actionShow_NebulaTextures", N_("Nebula Textures"), N_("Toggle Custom Nebula Textures"), "flagShow");
	addAction("actionShow_NebulaTextures_config_dialog", N_("Nebula Textures"), N_("Show settings dialog"), configDialog, "visible"); // no default hotkey
	if (QObject* manager = StelApp::getInstance().getModule("StelSkyLayerMgr"))
	{
		connect(manager, SIGNAL(collectionLoaded()), this, SLOT(handleCollectionLoaded()), Qt::UniqueConnection);
	}

	// Add a toolbar button
	try
	{
		StelGui* gui = dynamic_cast<StelGui*>(StelApp::getInstance().getGui());
		if (gui != Q_NULLPTR)
		{
			StelButton* nebulaTexturesButton = new StelButton(Q_NULLPTR,
				QPixmap(":/NebulaTextures/btNebulaTextures-on.png"),
				QPixmap(":/NebulaTextures/btNebulaTextures-off.png"),
				QPixmap(":/graphicGui/miscGlow32x32.png"),
				"actionShow_NebulaTextures",
				false,
				"actionShow_NebulaTextures_config_dialog");
			gui->getButtonBar()->addButton(nebulaTexturesButton, "065-pluginsGroup");
		}
	}
	catch (std::runtime_error& e)
	{
		qWarning() << "[NebulaTextures] unable to manage toolbar buttons for NebulaTextures plugin!"
			<< e.what();
	}
	handleCollectionLoaded();
}

// Draw method for the NebulaTextures module. Currently, it does nothing.
void NebulaTextures::draw(StelCore* core)
{
}

// Sets whether custom textures should be shown and refreshes the texture display.
void NebulaTextures::setShow(bool b)
{
	if (getShow() == b) return;
	configDialog->setShowCustomTextures(b);
	TileManager tileManager;
	if (!tileManager.setTileVisible(CustomTextureName, b) && b)
	{
		QString error;
		if (!refreshCustomTextures(&error) && !error.isEmpty())
			qWarning() << "[NebulaTextures] Failed to refresh custom textures:" << error;
	}
	if (b && getAvoidAreaConflict()) tileManager.resolveConflicts(DefaultTextureName, CustomTextureName);
	else { tileManager.restoreConflicts(); }
	emit showChanged(b);
}

// Returns whether custom textures are currently displayed.
bool NebulaTextures::getShow() const
{
	return StelApp::getInstance().getSettings()->value(ConfigPrefix + QStringLiteral("/showCustomTextures"), false).toBool();
}

void NebulaTextures::handleCollectionLoaded()
{
	TileManager tileManager;
	if (tileManager.getTile(CustomTextureName))
	{
		if (getShow() && getAvoidAreaConflict()) tileManager.resolveConflicts(DefaultTextureName, CustomTextureName);
		return;
	}
	QString error;
	if (!refreshCustomTextures(&error) && !error.isEmpty())
		qWarning() << "[NebulaTextures] Runtime custom texture refresh failed:" << error;
}

QString NebulaTextures::customConfigPath() const
{
	return StelFileMgr::getUserDir() + CustomConfigFile;
}

bool NebulaTextures::getAvoidAreaConflict() const
{
	return StelApp::getInstance().getSettings()->value(ConfigPrefix + QStringLiteral("/avoidAreaConflict"), false).toBool();
}

void NebulaTextures::setAvoidAreaConflict(bool enabled)
{
	if (getAvoidAreaConflict() == enabled) return;
	StelApp::getInstance().getSettings()->setValue(ConfigPrefix + QStringLiteral("/avoidAreaConflict"), enabled);
	TileManager tileManager;
	if (enabled && getShow()) tileManager.resolveConflicts(DefaultTextureName, CustomTextureName);
	else tileManager.restoreConflicts();
}

QJsonObject NebulaTextures::textureItemStatus(const QJsonObject& tile) const
{
	QJsonObject item;
	const QString imageUrl = tile.value(QStringLiteral("imageUrl")).toString().trimmed();
	item[QStringLiteral("imageUrl")] = imageUrl;
	item[QStringLiteral("credit")] = tile.value(QStringLiteral("imageCredits")).toObject().value(QStringLiteral("short")).toString();
	item[QStringLiteral("minResolution")] = tile.value(QStringLiteral("minResolution")).toDouble();
	item[QStringLiteral("maxBrightness")] = tile.value(QStringLiteral("maxBrightness")).toDouble();
	QString mappingError;
	QJsonArray corners;
	const bool mappingValid = readCorners(tile, &corners, &mappingError);
	item[QStringLiteral("mappingValid")] = mappingValid;
	item[QStringLiteral("mappingError")] = mappingError;
	if (mappingValid)
	{
		const QPair<double, double> center = SkyCoords::calculateCenter(corners);
		item[QStringLiteral("centerRaDeg")] = center.first;
		item[QStringLiteral("centerDecDeg")] = center.second;
	}

	const QString fileName = normalizedLocalImageName(imageUrl);
	if (fileName.isEmpty())
	{
		item[QStringLiteral("status")] = imageUrl.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive) || imageUrl.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive)
			? QStringLiteral("remote_blocked") : QStringLiteral("invalid_path");
		item[QStringLiteral("ready")] = false;
		return item;
	}
	const QFileInfo imageInfo(StelFileMgr::getUserDir() + PluginDirectory + fileName);
	item[QStringLiteral("path")] = imageInfo.absoluteFilePath();
	item[QStringLiteral("onDisk")] = imageInfo.exists() && imageInfo.isFile() && imageInfo.size() > 0;
	item[QStringLiteral("readable")] = imageInfo.isReadable();
	item[QStringLiteral("bytes")] = imageInfo.exists() ? imageInfo.size() : 0;
	if (!imageInfo.exists() || !imageInfo.isFile() || imageInfo.size() <= 0 || !imageInfo.isReadable())
	{
		item[QStringLiteral("status")] = QStringLiteral("missing_file");
		item[QStringLiteral("ready")] = false;
		return item;
	}
	const QString fingerprint = QString::number(imageInfo.size()) + ':' + QString::number(imageInfo.lastModified().toMSecsSinceEpoch());
	QJsonObject validation = imageValidationCache.value(imageInfo.absoluteFilePath());
	if (validation.value(QStringLiteral("fingerprint")).toString() != fingerprint)
	{
		QImageReader reader(imageInfo.absoluteFilePath());
		reader.setAutoTransform(true);
		const QImage decoded = reader.read();
		++imageDecodeCount;
		validation = QJsonObject{{QStringLiteral("fingerprint"), fingerprint}, {QStringLiteral("decoded"), !decoded.isNull()},
			{QStringLiteral("width"), decoded.width()}, {QStringLiteral("height"), decoded.height()},
			{QStringLiteral("error"), reader.errorString()}};
		imageValidationCache.insert(imageInfo.absoluteFilePath(), validation);
	}
	if (!validation.value(QStringLiteral("decoded")).toBool())
	{
		item[QStringLiteral("status")] = QStringLiteral("decode_failed");
		item[QStringLiteral("decodeError")] = validation.value(QStringLiteral("error"));
		item[QStringLiteral("ready")] = false;
		return item;
	}
	item[QStringLiteral("width")] = validation.value(QStringLiteral("width"));
	item[QStringLiteral("height")] = validation.value(QStringLiteral("height"));
	item[QStringLiteral("status")] = mappingValid ? QStringLiteral("ready") : QStringLiteral("invalid_mapping");
	item[QStringLiteral("ready")] = mappingValid;
	return item;
}

QJsonArray NebulaTextures::listTextures() const
{
	TextureConfigManager manager(customConfigPath(), CustomTextureName);
	QJsonArray items;
	if (!manager.load()) return items;
	for (const QJsonValue& value : manager.getSubTiles())
	{
		if (value.isObject()) items.append(textureItemStatus(value.toObject()));
	}
	return items;
}

QJsonObject NebulaTextures::validateTexture(const QString& imageUrl) const
{
	TextureConfigManager manager(customConfigPath(), CustomTextureName);
	if (!manager.load())
		return QJsonObject{{QStringLiteral("imageUrl"), imageUrl}, {QStringLiteral("status"), QStringLiteral("config_invalid")}, {QStringLiteral("error"), manager.getLastError()}, {QStringLiteral("ready"), false}};
	const QJsonObject tile = manager.getSubTileByImageUrl(imageUrl);
	if (tile.isEmpty())
		return QJsonObject{{QStringLiteral("imageUrl"), imageUrl}, {QStringLiteral("status"), QStringLiteral("not_found")}, {QStringLiteral("ready"), false}};
	return textureItemStatus(tile);
}

QJsonObject NebulaTextures::getTextureStatus() const
{
	QJsonObject status;
	TextureConfigManager manager(customConfigPath(), CustomTextureName);
	const QFileInfo configInfo(customConfigPath());
	const bool configLoaded = manager.load();
	status[QStringLiteral("enabled")] = getShow();
	status[QStringLiteral("avoidAreaConflict")] = getAvoidAreaConflict();
	status[QStringLiteral("configExists")] = configInfo.exists();
	status[QStringLiteral("configLoaded")] = configLoaded;
	status[QStringLiteral("configError")] = manager.getLastError();
	status[QStringLiteral("configPath")] = customConfigPath();
	status[QStringLiteral("offline")] = true;
	status[QStringLiteral("plateSolverAvailable")] = false;
	status[QStringLiteral("plateSolverPolicy")] = QStringLiteral("disabled_offline_image_upload");
	TileManager tileManager;
	status[QStringLiteral("layerLoaded")] = tileManager.getTile(CustomTextureName) != Q_NULLPTR;
	int readyCount = 0;
	int invalidCount = 0;
	QJsonArray items;
	if (configLoaded)
	{
		for (const QJsonValue& value : manager.getSubTiles())
		{
			if (!value.isObject())
			{
				++invalidCount;
				continue;
			}
			const QJsonObject item = textureItemStatus(value.toObject());
			item.value(QStringLiteral("ready")).toBool() ? ++readyCount : ++invalidCount;
			items.append(item);
		}
	}
	status[QStringLiteral("count")] = items.size();
	status[QStringLiteral("readyCount")] = readyCount;
	status[QStringLiteral("invalidCount")] = invalidCount;
	status[QStringLiteral("items")] = items;
	status[QStringLiteral("imageDecodeCount")] = static_cast<double>(imageDecodeCount);
	status[QStringLiteral("layerRebuildCount")] = static_cast<double>(layerRebuildCount);
	return status;
}

bool NebulaTextures::refreshCustomTextures(QString* error)
{
	TextureConfigManager manager(customConfigPath(), CustomTextureName);
	if (!manager.load())
	{
		if (error) *error = manager.getLastError();
		return false;
	}
	TileManager tileManager;
	if (manager.getSubTiles().isEmpty())
	{
		tileManager.restoreConflicts();
		tileManager.removeTile(CustomTextureName);
		imageValidationCache.clear();
		return true;
	}
	for (const QJsonValue& value : manager.getSubTiles())
	{
		if (!value.isObject() || !textureItemStatus(value.toObject()).value(QStringLiteral("ready")).toBool())
		{
			if (error) *error = QStringLiteral("Custom texture configuration contains invalid entries.");
			return false;
		}
	}
	tileManager.restoreConflicts();
	if (!tileManager.insertTileFromConfig(CustomConfigFile, CustomTextureName, getShow()))
	{
		if (error) *error = QStringLiteral("Unable to insert the custom texture layer.");
		return false;
	}
	if (!getShow()) tileManager.setTileVisible(CustomTextureName, false);
	else if (getAvoidAreaConflict()) tileManager.resolveConflicts(DefaultTextureName, CustomTextureName);
	++layerRebuildCount;
	return true;
}

bool NebulaTextures::gotoTexture(const QString& imageUrl, QString* error) const
{
	const QJsonObject item = validateTexture(imageUrl);
	if (!item.value(QStringLiteral("ready")).toBool())
	{
		if (error) *error = item.value(QStringLiteral("status")).toString();
		return false;
	}
	Vec3d position;
	StelUtils::spheToRect(item.value(QStringLiteral("centerRaDeg")).toDouble() * M_PI / 180.0,
		item.value(QStringLiteral("centerDecDeg")).toDouble() * M_PI / 180.0, position);
	StelMovementMgr* movement = GETSTELMODULE(StelMovementMgr);
	movement->setFlagTracking(false);
	movement->moveToJ2000(position, movement->getViewUpVectorJ2000(), movement->getAutoMoveDuration());
	return true;
}

bool NebulaTextures::removeTexture(const QString& imageUrl, QString* error)
{
	const QString fileName = normalizedLocalImageName(imageUrl);
	if (fileName.isEmpty())
	{
		if (error) *error = QStringLiteral("invalid_path");
		return false;
	}
	TextureConfigManager manager(customConfigPath(), CustomTextureName);
	if (!manager.load() || !manager.removeSubTileByImageUrl(fileName))
	{
		if (error) *error = manager.getLastError().isEmpty() ? QStringLiteral("not_found") : manager.getLastError();
		return false;
	}
	if (!manager.save())
	{
		if (error) *error = manager.getLastError();
		return false;
	}
	QFile::remove(StelFileMgr::getUserDir() + PluginDirectory + fileName);
	imageValidationCache.remove(StelFileMgr::getUserDir() + PluginDirectory + fileName);
	return refreshCustomTextures(error);
}

QJsonObject NebulaTextures::importTexture(const QJsonObject& request)
{
	QJsonObject result;
	const QString sourcePath = request.value(QStringLiteral("sourcePath")).toString().trimmed();
	const QFileInfo sourceInfo(sourcePath);
	if (!sourceInfo.exists() || !sourceInfo.isFile() || !sourceInfo.isReadable())
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("source_unreadable")}};
	QImageReader reader(sourcePath);
	reader.setAutoTransform(true);
	++imageDecodeCount;
	const QImage image = reader.read();
	if (image.isNull())
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("decode_failed")}, {QStringLiteral("detail"), reader.errorString()}};

	QJsonArray corners = request.value(QStringLiteral("corners")).toArray();
	if (!corners.isEmpty())
	{
		QJsonObject testTile{{QStringLiteral("worldCoords"), QJsonArray{corners}}};
		QString mappingError;
		if (!readCorners(testTile, Q_NULLPTR, &mappingError))
			return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), mappingError}};
	}
	else
	{
		double centerRa = request.value(QStringLiteral("centerRaDeg")).toDouble(std::numeric_limits<double>::quiet_NaN());
		double centerDec = request.value(QStringLiteral("centerDecDeg")).toDouble(std::numeric_limits<double>::quiet_NaN());
		double angularWidth = request.value(QStringLiteral("angularWidthDeg")).toDouble(0.0);
		StelMovementMgr* movement = GETSTELMODULE(StelMovementMgr);
		if (!std::isfinite(centerRa) || !std::isfinite(centerDec))
		{
			StelUtils::rectToSphe(&centerRa, &centerDec, movement->getViewDirectionJ2000());
			centerRa *= 180.0 / M_PI;
			centerDec *= 180.0 / M_PI;
		}
		if (angularWidth <= 0.0) angularWidth = movement->getCurrentFov();
		if (!std::isfinite(centerRa) || !std::isfinite(centerDec) || centerDec < -89.0 || centerDec > 89.0 || angularWidth < 0.01 || angularWidth > 120.0)
			return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("invalid_view_mapping")}};
		const double angularHeight = qBound(0.01, angularWidth * image.height() / qMax(1.0, static_cast<double>(image.width())), 120.0);
		const double decHalf = angularHeight * 0.5;
		const double raHalf = qMin(179.0, angularWidth * 0.5 / qMax(0.1, std::cos(centerDec * M_PI / 180.0)));
		const double bottom = qMax(-90.0, centerDec - decHalf);
		const double top = qMin(90.0, centerDec + decHalf);
		corners = QJsonArray{
			QJsonArray{normalizedDegrees(centerRa - raHalf), bottom},
			QJsonArray{normalizedDegrees(centerRa + raHalf), bottom},
			QJsonArray{normalizedDegrees(centerRa + raHalf), top},
			QJsonArray{normalizedDegrees(centerRa - raHalf), top}};
		result[QStringLiteral("mappingMode")] = QStringLiteral("current_view");
	}

	const QString suffix = sourceInfo.suffix().toLower();
	const QStringList allowed{QStringLiteral("png"), QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("gif"), QStringLiteral("tif"), QStringLiteral("tiff")};
	if (!allowed.contains(suffix))
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("unsupported_format")}};
	const QString destinationDirectory = StelFileMgr::getUserDir() + PluginDirectory;
	if (!QDir().mkpath(destinationDirectory))
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("storage_unavailable")}};
	QString baseName = sourceInfo.completeBaseName();
	baseName.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9._-]+")), QStringLiteral("_"));
	if (baseName.isEmpty()) baseName = QStringLiteral("texture");
	const QString fileName = QStringLiteral("%1_%2.%3").arg(baseName, QUuid::createUuid().toString(QUuid::WithoutBraces), suffix);
	const QString destinationPath = destinationDirectory + fileName;
	QFile sourceFile(sourcePath);
	QSaveFile destinationFile(destinationPath);
	if (!sourceFile.open(QIODevice::ReadOnly) || !destinationFile.open(QIODevice::WriteOnly))
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("copy_failed")},
			{QStringLiteral("detail"), sourceFile.errorString() + "; " + destinationFile.errorString()}};
	while (!sourceFile.atEnd())
	{
		const QByteArray bytes = sourceFile.read(1024 * 1024);
		if (sourceFile.error() != QFileDevice::NoError || destinationFile.write(bytes) != bytes.size())
			return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("copy_failed")},
				{QStringLiteral("detail"), sourceFile.errorString() + "; " + destinationFile.errorString()}};
	}
	if (!destinationFile.commit())
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("copy_failed")},
			{QStringLiteral("detail"), destinationFile.errorString()}};

	TextureConfigManager manager(customConfigPath(), CustomTextureName);
	if (!manager.load())
	{
		QFile::remove(destinationPath);
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("config_invalid")}, {QStringLiteral("detail"), manager.getLastError()}};
	}
	const double brightness = qBound(1.0, request.value(QStringLiteral("maxBrightness")).toDouble(13.5), 30.0);
	manager.addSubTile(fileName, corners, 0.2, brightness);
	if (!manager.save())
	{
		QFile::remove(destinationPath);
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("config_write_failed")}, {QStringLiteral("detail"), manager.getLastError()}};
	}
	const QFileInfo importedInfo(destinationPath);
	imageValidationCache.insert(destinationPath, QJsonObject{
		{QStringLiteral("fingerprint"), QString::number(importedInfo.size()) + ':' + QString::number(importedInfo.lastModified().toMSecsSinceEpoch())},
		{QStringLiteral("decoded"), true}, {QStringLiteral("width"), image.width()}, {QStringLiteral("height"), image.height()}});
	QString refreshError;
	if (!refreshCustomTextures(&refreshError))
		return QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("layer_refresh_failed")}, {QStringLiteral("detail"), refreshError}, {QStringLiteral("imageUrl"), fileName}};
	result[QStringLiteral("ok")] = true;
	result[QStringLiteral("imageUrl")] = fileName;
	result[QStringLiteral("width")] = image.width();
	result[QStringLiteral("height")] = image.height();
	result[QStringLiteral("offline")] = true;
	return result;
}
