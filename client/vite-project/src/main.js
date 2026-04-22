import 'ol/ol.css';
import Map from 'ol/Map';
import View from 'ol/View';
import TileLayer from 'ol/layer/Tile';
import OSM from 'ol/source/OSM';
import ImageLayer from 'ol/layer/Image';
import ImageWMS from 'ol/source/ImageWMS';
import VectorLayer from 'ol/layer/Vector';
import VectorSource from 'ol/source/Vector';
import GeoJSON from 'ol/format/GeoJSON';
import { Style, Fill, Stroke } from 'ol/style';

const buildingsLayer = new ImageLayer({
  source: new ImageWMS({
    url: 'http://localhost:8080/geoserver/gis/wms',
    params: {
      LAYERS: 'gis:buildings',
      TILED: true,
      FORMAT: 'image/png8'
    },
    ratio: 1,
    serverType: 'geoserver'
  })
});

// Добавляем слой дорог
const roadsLayer = new ImageLayer({
  source: new ImageWMS({
    url: 'http://localhost:8080/geoserver/gis/wms',
    params: {
      LAYERS: 'gis:roads',
      TILED: true,
      FORMAT: 'image/png8'
    },
    ratio: 1,
    serverType: 'geoserver'
  })
});

// Добавляем слой POI
const poiLayer = new ImageLayer({
  source: new ImageWMS({
    url: 'http://localhost:8080/geoserver/gis/wms',
    params: {
      LAYERS: 'gis:poi',
      TILED: true,
      FORMAT: 'image/png8'
    },
    ratio: 1,
    serverType: 'geoserver'
  })
});

const styleFunction = (feature) => {
  const sourceType = feature.get('source_type');
  let color;
  
  switch(sourceType) {
    case 'my':
      color = '#4CAF50';
      break;
    case 'osm':
      color = '#2196F3';
      break;
    case 'ml':
      color = '#FF9800';
      break;
    default:
      color = '#888888';
  }
  
  return new Style({
    fill: new Fill({ color: color + '80' }), // полупрозрачный
    stroke: new Stroke({ color: color, width: 1 })
  });
};

// Слой с Overture данными
const overtureLayer = new VectorLayer({
  source: new VectorSource({
    url: '/overture.json',
    format: new GeoJSON()
  }),
  style: styleFunction
});

const map = new Map({
  target: 'map',
  layers: [
    new TileLayer({
      source: new OSM()
    }),
    buildingsLayer,
    roadsLayer,
    poiLayer,
    overtureLayer
  ],
  view: new View({
    center: [5615800, 7031700],
    zoom: 14
  })
});