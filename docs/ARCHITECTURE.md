# Техническая архитектура

## Стек первого прототипа
- Vite;
- TypeScript;
- Phaser 3 для сцены, ввода, камеры и отрисовки;
- HTML/CSS для панелей интерфейса.

Не добавлять React и дополнительные библиотеки без конкретной необходимости. Запуск локально — одной понятной npm-командой.

## Модули
- scene — создание сцены и слоёв;
- camera — перемещение и масштаб;
- isometric-grid — преобразование координат;
- placement — проверка footprint и занятых клеток;
- furniture — экземпляры мебели и поворот;
- asset-registry — загрузка манифеста и выбор спрайта;
- input — выбор, drag-and-drop, горячие клавиши;
- ui — панели и подсказки.

## Координаты
Логическое положение хранится в gridX/gridY. Для изометрической клетки:
- screenX = (gridX - gridY) × tileWidth / 2
- screenY = (gridX + gridY) × tileHeight / 2

Смещение сцены и anchor спрайта учитываются отдельно.

## Формат мебельного ассета
~~~json
{
  "id": "desk_standard",
  "name": "Рабочий стол",
  "footprint": { "width": 2, "height": 1 },
  "anchor": { "x": 0.5, "y": 0.9 },
  "defaultOrientation": "south_east",
  "orientations": {
    "north_east": "assets/furniture/desk_standard/ne.png",
    "south_east": "assets/furniture/desk_standard/se.png",
    "south_west": "assets/furniture/desk_standard/sw.png",
    "north_west": "assets/furniture/desk_standard/nw.png"
  },
  "fallbackOrientation": "south_east"
}
~~~

У объекта может быть 1, 2 или 4 варианта. Footprint описывает клетки, а не размеры PNG. При повороте на 90 градусов ширина и высота footprint меняются местами. Для несимметричных объектов поворачивается схема занятых клеток.

## Каталоги
~~~text
public/assets/furniture/desk_standard/ne.png
public/assets/furniture/desk_standard/se.png
public/assets/furniture/cabinet_low/se.png
src/data/furniture.json
~~~

Пути задаются в манифесте, а не в компонентах. Тестовые изображения и пользовательские PNG используют один Asset Registry.

## Размещение и сортировка
Предмет хранит ID, grid position, footprint и orientation. Drag-and-drop показывает preview, затем подтверждает или отклоняет размещение. При ошибке предмет возвращается на прежнее место. Y-sort определяется точкой опоры; визуальная высота PNG не влияет на footprint.

## Будущая симуляция и сохранение
Симуляция использует контролируемый шаг времени, независимый от FPS. В будущем сохранять ID, координаты и ориентацию, а не копии изображений. Формат сохранения версионировать.

## Тестирование
Координатные преобразования, поворот footprint и коллизии тестируются отдельно от отрисовки.
